/*
 * iSH sandbox host entry for HarmonyOS.
 *
 * HarmonyOS refuses to exec any ELF from an app (see docs/SANDBOX.md), so the
 * guest Linux userland cannot run as host processes. This native child process
 * instead hosts the iSH ARM64 kernel from OpenMinis' ish-arm64 branch: the
 * kernel loads and interprets guest ELF images itself, and the guest's stdio
 * is attached to host pipes/files through iSH's adhoc realfs descriptors.
 *
 * Wire format (request file, one key=value per line):
 *   rootfs=<dir containing meta.db and data/>
 *   output=<file that receives stdout+stderr>
 *   timeout_ms=<optional, default 30000>
 *   command=<shell command line, last field>
 *
 * The guest runs `/bin/sh -c <command>`. When the shell exits, the exit status
 * is appended to the output file and the child process exits. ArkTS starts
 * this with childProcessManager.startNativeChildProcess(
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
    char command[kMaxCommand];
    int timeoutMs;
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
    request->timeoutMs = 30000;
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
        } else if (strncmp(line, "timeout_ms=", 11) == 0) {
            request->timeoutMs = atoi(line + 11);
        } else if (strncmp(line, "command=", 8) == 0) {
            snprintf(request->command, sizeof(request->command), "%s", line + 8);
        }
    }
    free(text);
    return request->rootfs[0] != '\0' && request->output[0] != '\0' &&
           request->command[0] != '\0';
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

int run(Request *request) {
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

    char argvBuffer[kMaxCommand + 64];
    size_t argvPos = 0;
    argvPos = appendArg(argvBuffer, sizeof(argvBuffer), argvPos, "/bin/sh");
    argvPos = appendArg(argvBuffer, sizeof(argvBuffer), argvPos, "-c");
    argvPos = appendArg(argvBuffer, sizeof(argvBuffer), argvPos,
                        request->command);
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

    err = do_execve("/bin/sh", 3, argvBuffer, envpBuffer);
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

    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    int timeout = request->timeoutMs > 0 ? request->timeoutMs : 30000;
    deadline.tv_sec += timeout / 1000;
    deadline.tv_nsec += (long)(timeout % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }

    while (sem_timedwait(&g_exitSem, &deadline) != 0 && errno == EINTR) {
    }

    /*
     * fd 1 is the same open file description as the guest's stdout, so this
     * lands after whatever the command printed.
     */
    if (g_exitCode >= 0 || g_exitSignal != 0) {
        dprintf(STDOUT_FILENO, "\n[sandbox exit=%d signal=%d]\n",
                g_exitCode, g_exitSignal);
    } else {
        dprintf(STDOUT_FILENO, "\n[sandbox timeout after %d ms]\n", timeout);
    }
    fsync(STDOUT_FILENO);
    return 0;
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

    int err = run(&request);
    sem_destroy(&g_exitSem);
    _exit(err < 0 ? 1 : 0);
}
