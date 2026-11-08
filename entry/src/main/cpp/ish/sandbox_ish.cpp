/*
 * iSH sandbox host entry for HarmonyOS.
 *
 * HarmonyOS refuses to exec any ELF from an app (see docs/SANDBOX.md), so the
 * guest Linux userland cannot run as host processes. This native child process
 * instead hosts the iSH ARM64 kernel from OpenMinis' ish-arm64 branch: the
 * kernel loads and interprets guest ELF images itself, and the guest's stdio
 * is attached to host pipes/files through iSH's adhoc realfs descriptors.
 *
 * Host directory request (written once, one key=value per line):
 *   rootfs=<dir containing meta.db and data/>
 *   output=<file that receives stdout+stderr, appended for the daemon's life>
 *   commands=<file the app rewrites per command>
 *   workspace=<optional host dir mounted at /var/minis/workspace>
 *   memory=<optional host dir mounted at /var/minis/memory>
 *   attachments=<optional host dir mounted at /var/minis/attachments>
 *   skills=<optional host dir mounted at /var/minis/skills>
 *
 * The guest keeps one `/bin/sh` alive as PID 1 and reads a script stream from
 * stdin. Each command file is `id=<n>\n<command text>`; the harness feeds
 *   { <command>
 *   }; printf "\n[sandbox exit=%d id=<n>]\n" "$?"
 * into the shell, so shell state (cwd, variables) survives between calls and
 * the exit marker is written by the shell itself. The guest's PID 1 must never
 * exit: when it does, iSH tears down the whole native process.
 *
 * ArkTS starts this with childProcessManager.startNativeChildProcess(
 *   'libishsandbox.so:Main', { entryParams: <request path> }).
 */

#include <AbilityKit/native_child_process.h>

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <semaphore.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

/*
 * Minimal declarations from the iSH headers. Keeping the ABI surface explicit
 * here means the app build does not need the whole GPL kernel header tree on
 * its include path; the prebuilt archive carries the implementation.
 */
extern "C" {

struct fs_ops;
struct fd;
struct task;

extern const struct fs_ops fakefs;
extern const struct fs_ops procfs;
extern const struct fs_ops devptsfs;
/* fs/mount.c: passthrough to a host directory, used for user mounts. */
extern const struct fs_ops realfs;
extern __thread struct task *current;
extern void (*exit_hook)(struct task *task, int code);

int mount_root(const struct fs_ops *fs, const char *source);
int become_first_process(void);
int become_new_init_child(void);
int do_mount(const struct fs_ops *fs, const char *source, const char *point,
             const char *info, int flags);
int generic_mkdirat(struct fd *at, const char *path, unsigned int mode);
int generic_mknodat(struct fd *at, const char *path, unsigned int mode,
                    unsigned int dev);
int create_piped_stdio(void);
int do_execve(const char *file, size_t argc, const char *argv,
              const char *envp);
int task_start(struct task *task);


/* fs/path.h: generic_* interprets this sentinel as current->pwd. */
static struct fd *const kAtPwd = (struct fd *)-2;

/* fs/dev.h */
static inline uint32_t dev_make(int major, int minor) {
    return (uint32_t)(((minor & 0xfff00) << 12) | (major << 8) | (minor & 0xff));
}

/* fs/devices.h */
enum {
    MEM_MAJOR = 1,
    DEV_NULL_MINOR = 3,
    DEV_ZERO_MINOR = 5,
    DEV_FULL_MINOR = 7,
    DEV_RANDOM_MINOR = 8,
    DEV_URANDOM_MINOR = 9,
    TTY_CONSOLE_MAJOR = 4,
    TTY_ALTERNATE_MAJOR = 5,
    DEV_TTY_MINOR = 0,
    DEV_CONSOLE_MINOR = 1,
    DEV_PTMX_MINOR = 2,
};

} // extern "C"

namespace {

constexpr size_t kMaxRequest = 64 * 1024;
constexpr size_t kMaxCommand = 16 * 1024;

struct Request {
    char rootfs[512];
    char output[512];
    char commands[512];
    char workspace[512];
    char memory[512];
    char attachments[512];
    char skills[512];
};

sem_t g_exitSem;
struct task *g_shell = nullptr;
int g_exitCode = -1;
int g_exitSignal = 0;

/** Runs on the guest thread that is exiting, under pids_lock. */
void onGuestExit(struct task *task, int code) {
    if (task != g_shell) {
        return;
    }
    g_exitCode = (code >> 8) & 0xff;
    g_exitSignal = code & 0xff;
    sem_post(&g_exitSem);
}

void fail(const char *stage, int err) {
    dprintf(STDOUT_FILENO, "\n[sandbox] %s failed: %d (%s)\n", stage, err,
            strerror(err < 0 ? -err : err));
}

/** Non-fatal: the sandbox still runs without the optional mount. */
void warn(const char *stage, int err) {
    dprintf(STDOUT_FILENO, "\n[sandbox warn] %s failed: %d (%s)\n", stage, err,
            strerror(err < 0 ? -err : err));
}

bool readFile(const char *path, char *buffer, size_t capacity) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        return false;
    }
    size_t used = 0;
    for (;;) {
        ssize_t n = read(fd, buffer + used, capacity - 1 - used);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            close(fd);
            return false;
        }
        if (n == 0) {
            break;
        }
        used += (size_t)n;
        if (used + 1 >= capacity) {
            break;
        }
    }
    close(fd);
    buffer[used] = '\0';
    return true;
}

bool parseRequest(const char *path, Request *request) {
    char *text = static_cast<char *>(malloc(kMaxRequest));
    if (text == nullptr) {
        return false;
    }
    bool ok = readFile(path, text, kMaxRequest);
    if (!ok) {
        free(text);
        return false;
    }
    char *cursor = text;
    while (cursor != nullptr && *cursor != '\0') {
        char *line = cursor;
        char *newline = strchr(cursor, '\n');
        if (newline != nullptr) {
            *newline = '\0';
            cursor = newline + 1;
        } else {
            cursor = nullptr;
        }
        if (strncmp(line, "rootfs=", 7) == 0) {
            snprintf(request->rootfs, sizeof(request->rootfs), "%s", line + 7);
        } else if (strncmp(line, "output=", 7) == 0) {
            snprintf(request->output, sizeof(request->output), "%s", line + 7);
        } else if (strncmp(line, "commands=", 9) == 0) {
            snprintf(request->commands, sizeof(request->commands), "%s", line + 9);
        } else if (strncmp(line, "workspace=", 10) == 0) {
            snprintf(request->workspace, sizeof(request->workspace), "%s", line + 10);
        } else if (strncmp(line, "memory=", 7) == 0) {
            snprintf(request->memory, sizeof(request->memory), "%s", line + 7);
        } else if (strncmp(line, "attachments=", 12) == 0) {
            snprintf(request->attachments, sizeof(request->attachments), "%s",
                     line + 12);
        } else if (strncmp(line, "skills=", 7) == 0) {
            snprintf(request->skills, sizeof(request->skills), "%s", line + 7);
        }
    }
    free(text);
    return request->rootfs[0] != '\0' && request->output[0] != '\0' &&
           request->commands[0] != '\0';
}

/** Attach guest stdio to the output file before the guest process starts. */
int attachStdio(const char *output) {
    int out = open(output, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) {
        return -1;
    }
    if (dup2(out, STDOUT_FILENO) < 0 || dup2(out, STDERR_FILENO) < 0 ||
        dup2(out, 666) < 0) {
        close(out);
        return -1;
    }
    int devNull = open("/dev/null", O_RDONLY);
    if (devNull >= 0) {
        dup2(devNull, STDIN_FILENO);
        close(devNull);
    }
    if (out > 2) {
        close(out);
    }
    return 0;
}

int createDeviceNodes() {
    generic_mkdirat(kAtPwd, "/dev", 0755);
    generic_mkdirat(kAtPwd, "/dev/pts", 0755);

    struct Node {
        const char *path;
        int major;
        int minor;
    };
    const Node nodes[] = {
        {"/dev/tty1", TTY_CONSOLE_MAJOR, 1},
        {"/dev/tty", TTY_ALTERNATE_MAJOR, DEV_TTY_MINOR},
        {"/dev/console", TTY_ALTERNATE_MAJOR, DEV_CONSOLE_MINOR},
        {"/dev/ptmx", TTY_ALTERNATE_MAJOR, DEV_PTMX_MINOR},
        {"/dev/null", MEM_MAJOR, DEV_NULL_MINOR},
        {"/dev/zero", MEM_MAJOR, DEV_ZERO_MINOR},
        {"/dev/full", MEM_MAJOR, DEV_FULL_MINOR},
        {"/dev/random", MEM_MAJOR, DEV_RANDOM_MINOR},
        {"/dev/urandom", MEM_MAJOR, DEV_URANDOM_MINOR},
    };
    int last = 0;
    for (size_t i = 0; i < sizeof(nodes) / sizeof(nodes[0]); i++) {
        int err = generic_mknodat(kAtPwd, nodes[i].path,
                                  S_IFCHR | 0666,
                                  dev_make(nodes[i].major, nodes[i].minor));
        /* -EEXIST is fine: the image may already carry a node. */
        if (err < 0) {
            last = err;
        }
    }
    return last;
}

/** Build the double-NUL-terminated argv/envp blob iSH expects. */
size_t appendArg(char *buffer, size_t capacity, size_t pos, const char *arg) {
    size_t length = strlen(arg) + 1;
    if (pos + length + 1 >= capacity) {
        return pos;
    }
    memcpy(buffer + pos, arg, length);
    return pos + length;
}

/** Host fd feeding the guest shell's stdin, held open for the daemon's life. */
int g_commandWrite = -1;

/** Mount one host directory into the guest, creating the mount point. */
void mountGuestDir(const char *host, const char *point) {
    if (host[0] == '\0') {
        return;
    }
    generic_mkdirat(kAtPwd, "/var", 0755);
    generic_mkdirat(kAtPwd, "/var/minis", 0755);
    generic_mkdirat(kAtPwd, point, 0755);
    int err = do_mount(&realfs, host, point, "", 0);
    if (err < 0) {
        // A missing or unreadable host directory only disables that mount.
        warn("mount_realfs", err);
    }
}

bool writeAll(int fd, const char *data, size_t length) {
    while (length > 0) {
        ssize_t written = write(fd, data, length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        data += written;
        length -= (size_t)written;
    }
    return true;
}

struct Command {
    long id;
    size_t length;
    char text[kMaxCommand];
};

/**
 * Read `id=<n>\n<command text>`. The app replaces the file atomically, so a
 * prefix that does not parse yet (or a missing file) just means "no command".
 */
bool readCommand(const char *path, Command *command) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        return false;
    }
    char buffer[kMaxCommand + 64];
    ssize_t used = 0;
    while (used < (ssize_t)sizeof(buffer) - 1) {
        ssize_t n = read(fd, buffer + used, sizeof(buffer) - 1 - (size_t)used);
        if (n <= 0) {
            break;
        }
        used += n;
    }
    close(fd);
    buffer[used] = '\0';
    char *newline = strchr(buffer, '\n');
    if (newline == nullptr || strncmp(buffer, "id=", 3) != 0) {
        return false;
    }
    char *end = nullptr;
    long id = strtol(buffer + 3, &end, 10);
    if (end == buffer + 3) {
        return false;
    }
    size_t length = (size_t)used - (size_t)(newline + 1 - buffer);
    if (length == 0 || length >= sizeof(command->text)) {
        return false;
    }
    memcpy(command->text, newline + 1, length);
    command->text[length] = '\0';
    command->length = length;
    command->id = id;
    return true;
}

int serve(Request *request) {
    char rootData[600];
    snprintf(rootData, sizeof(rootData), "%s/data", request->rootfs);

    int err = mount_root(&fakefs, rootData);
    if (err < 0) {
        fail("mount_root", err);
        return err;
    }

    err = become_first_process();
    if (err < 0) {
        fail("become_first_process", err);
        return err;
    }

    createDeviceNodes();

    do_mount(&procfs, "proc", "/proc", "", 0);
    do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);
    // User mounts are live host directories: the app's workspace and memory
    // directory are the same files the file tools already work on.
    mountGuestDir(request->workspace, "/var/minis/workspace");
    mountGuestDir(request->memory, "/var/minis/memory");
    // Chat attachments (images, files); the shell can process the same media
    // read_image sees, for example with Python or file(1).
    mountGuestDir(request->attachments, "/var/minis/attachments");
    // Imported skills, so a script can read a skill's reference files the same
    // way read_skill returns its body.
    mountGuestDir(request->skills, "/var/minis/skills");

    err = become_new_init_child();
    if (err < 0) {
        fail("become_new_init_child", err);
        return err;
    }

    err = create_piped_stdio();
    if (err < 0) {
        fail("create_piped_stdio", err);
        return err;
    }

    // No -c: the shell reads a script stream from stdin, which keeps PID 1
    // (and with it the whole native process) alive between commands.
    char argvBuffer[64];
    size_t argvPos = 0;
    argvPos = appendArg(argvBuffer, sizeof(argvBuffer), argvPos, "/bin/sh");
    argvBuffer[argvPos] = '\0';
    argvBuffer[argvPos + 1] = '\0';

    char envpBuffer[1024];
    size_t envpPos = 0;
    envpPos = appendArg(envpBuffer, sizeof(envpBuffer), envpPos, "HOME=/root");
    envpPos = appendArg(envpBuffer, sizeof(envpBuffer), envpPos,
                        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:"
                        "/usr/bin:/sbin:/bin");
    envpPos = appendArg(envpBuffer, sizeof(envpBuffer), envpPos,
                        "TERM=dumb");
    envpPos = appendArg(envpBuffer, sizeof(envpBuffer), envpPos,
                        "LANG=C.UTF-8");
    envpPos = appendArg(envpBuffer, sizeof(envpBuffer), envpPos, "NO_COLOR=1");
    envpBuffer[envpPos] = '\0';
    envpBuffer[envpPos + 1] = '\0';

    err = do_execve("/bin/sh", 1, argvBuffer, envpBuffer);
    if (err < 0) {
        fail("do_execve", err);
        return err;
    }

    g_shell = current;
    exit_hook = onGuestExit;

    err = task_start(g_shell);
    if (err < 0) {
        fail("task_start", err);
        return err;
    }

    dprintf(STDOUT_FILENO, "[sandbox ready]\n");
    fsync(STDOUT_FILENO);

    long lastId = 0;
    while (true) {
        Command command = {};
        if (!readCommand(request->commands, &command)) {
            struct timespec pause = {0, 80 * 1000 * 1000};
            nanosleep(&pause, nullptr);
            continue;
        }
        if (command.id < 0) {
            dprintf(STDOUT_FILENO, "[sandbox stopped]\n");
            fsync(STDOUT_FILENO);
            return 0;
        }
        if (command.id <= lastId) {
            struct timespec pause = {0, 80 * 1000 * 1000};
            nanosleep(&pause, nullptr);
            continue;
        }
        lastId = command.id;

        // The shell prints the marker itself: when PID 1 exits iSH tears the
        // process down before the harness can append anything.
        char suffix[192];
        int suffixLength = snprintf(suffix, sizeof(suffix),
            "\n}; __minis_status=$?; printf \"\\n[sandbox exit=%%d id=%ld]\\n\""
            " \"$__minis_status\"\n", command.id);
        if (suffixLength <= 0 ||
            !writeAll(g_commandWrite, "{ ", 2) ||
            !writeAll(g_commandWrite, command.text, command.length) ||
            !writeAll(g_commandWrite, suffix, (size_t)suffixLength)) {
            dprintf(STDOUT_FILENO, "[sandbox] cannot feed command %ld\n",
                    command.id);
            fsync(STDOUT_FILENO);
            return -1;
        }
    }
}

} // namespace

extern "C" __attribute__((visibility("default"))) void Main(
    NativeChildProcess_Args args) {
    sem_init(&g_exitSem, 0, 0);

    const Request empty = {};
    (void)empty;

    Request request = {};
    // Attach early so boot diagnostics land in the same report the UI reads.
    char requestPath[1024] = {0};
    if (args.entryParams != nullptr) {
        snprintf(requestPath, sizeof(requestPath), "%s", args.entryParams);
    }
    if (!parseRequest(requestPath, &request)) {
        static char fallback[128];
        snprintf(fallback, sizeof(fallback), "%s.out", requestPath);
        attachStdio(fallback);
        dprintf(STDOUT_FILENO, "[sandbox] cannot parse request %s\n",
                requestPath);
        _exit(2);
    }

    if (attachStdio(request.output) < 0) {
        _exit(2);
    }

    // attachStdio points stdin at /dev/null; replace it with the read end of
    // the pipe the harness keeps open and writes command scripts into.
    int stdinPipe[2];
    if (pipe(stdinPipe) < 0 || dup2(stdinPipe[0], STDIN_FILENO) < 0) {
        _exit(2);
    }
    close(stdinPipe[0]);
    g_commandWrite = stdinPipe[1];

    int err = serve(&request);
    sem_destroy(&g_exitSem);
    _exit(err < 0 ? 1 : 0);
}
