/*
 * On-device sandbox feasibility probe.
 *
 * HarmonyOS runs on the HongMeng kernel, not on Linux. Before committing to a
 * sandbox design (PRoot vs an in-process emulator vs a remote helper) this
 * native child process reports what the kernel and SELinux policy actually
 * allow: executing a system binary, executing a copy in app storage, ptrace,
 * executable anonymous memory, and mount namespaces.
 *
 * The child is started from ArkTS with
 *   childProcessManager.startNativeChildProcess('libsandboxprobe.so:Main',
 *     { entryParams: <report path> })
 * and exits after Main returns. The report is plain text so the UI can show
 * and copy it without another protocol.
 */

#include <AbilityKit/native_child_process.h>

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

namespace {

FILE *g_report = nullptr;
/**
 * unshare() is killed by the seccomp filter with SIGSYS, which makes the
 * system record a native crash for this child. The answer is already known,
 * so only run the live test when the caller explicitly asks (entryParams
 * suffixed with "|deep"); otherwise report the observed result.
 */
bool g_deep = false;

void line(const char *key, const char *value) {
    if (g_report != nullptr) {
        fprintf(g_report, "%s=%s\n", key, value);
        fflush(g_report);
    }
}

void lineInt(const char *key, long value) {
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%ld", value);
    line(key, buffer);
}

void lineErrno(const char *key, int error) {
    char buffer[128];
    snprintf(buffer, sizeof(buffer), "%d (%s)", error, strerror(error));
    line(key, buffer);
}

/** Run `/system/bin/sh -c <command>` and describe the outcome. */
void probeSpawn(const char *label, const char *path, const char *command) {
    int pipeFd[2] = {-1, -1};
    if (pipe(pipeFd) != 0) {
        lineErrno(label, errno);
        return;
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipeFd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipeFd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipeFd[0]);

    pid_t pid = -1;
    char *argv[] = {
        const_cast<char *>(path),
        const_cast<char *>("-c"),
        const_cast<char *>(command),
        nullptr,
    };
    int rc = posix_spawn(&pid, path, &actions, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipeFd[1]);

    char output[512];
    ssize_t used = 0;
    if (rc == 0) {
        int status = 0;
        waitpid(pid, &status, 0);
        char chunk[128];
        ssize_t n = 0;
        while ((n = read(pipeFd[0], chunk, sizeof(chunk))) > 0 &&
               used + n < static_cast<ssize_t>(sizeof(output) - 1)) {
            memcpy(output + used, chunk, static_cast<size_t>(n));
            used += n;
        }
        output[used] = '\0';
        for (ssize_t i = 0; i < used; i++) {
            if (output[i] == '\n' || output[i] == '\r') {
                output[i] = ' ';
            }
        }
        char buffer[640];
        snprintf(buffer, sizeof(buffer), "ok exit=%d out=%s",
                 WIFEXITED(status) ? WEXITSTATUS(status) : -1, output);
        line(label, buffer);
    } else {
        lineErrno(label, rc);
    }
    close(pipeFd[0]);
}

/** Copy a readable ELF into app storage and try to execute the copy. */
void probeFileExec(const char *source, const char *target) {
    int in = open(source, O_RDONLY);
    if (in < 0) {
        lineErrno("data_exec_copy", errno);
        return;
    }
    int out = open(target, O_WRONLY | O_CREAT | O_TRUNC, 0755);
    if (out < 0) {
        lineErrno("data_exec_copy", errno);
        close(in);
        return;
    }
    char buffer[16384];
    ssize_t n = 0;
    while ((n = read(in, buffer, sizeof(buffer))) > 0) {
        if (write(out, buffer, static_cast<size_t>(n)) != n) {
            break;
        }
    }
    close(in);
    close(out);
    chmod(target, 0755);
    probeSpawn("data_exec", target, "ignored");
}

/** Copy /system/bin/sh into app storage and try to execute the copy. */
void probeDataExec(const char *dir) {
    const char *target = nullptr;
    char path[512];
    snprintf(path, sizeof(path), "%s/sh-copy", dir);
    target = path;

    int in = open("/system/bin/sh", O_RDONLY);
    if (in < 0) {
        lineErrno("data_exec_copy", errno);
        return;
    }
    int out = open(target, O_WRONLY | O_CREAT | O_TRUNC, 0755);
    if (out < 0) {
        lineErrno("data_exec_copy", errno);
        close(in);
        return;
    }
    char buffer[16384];
    ssize_t n = 0;
    while ((n = read(in, buffer, sizeof(buffer))) > 0) {
        if (write(out, buffer, static_cast<size_t>(n)) != n) {
            break;
        }
    }
    close(in);
    close(out);
    chmod(target, 0755);
    probeSpawn("data_exec", target, "echo data-exec-ok");
}

void probePtrace() {
    pid_t pid = fork();
    if (pid < 0) {
        lineErrno("ptrace", errno);
        return;
    }
    if (pid == 0) {
        if (ptrace(PTRACE_TRACEME, 0, nullptr, nullptr) != 0) {
            _exit(errno == 0 ? 1 : errno);
        }
        raise(SIGSTOP);
        _exit(0);
    }
    int status = 0;
    pid_t waited = waitpid(pid, &status, 0);
    if (waited < 0) {
        lineErrno("ptrace", errno);
        return;
    }
    if (!WIFSTOPPED(status)) {
        line("ptrace", "child did not stop (TRACEME rejected)");
        return;
    }
    long rc = ptrace(PTRACE_CONT, pid, nullptr, nullptr);
    if (rc != 0) {
        lineErrno("ptrace", errno);
        return;
    }
    waitpid(pid, &status, 0);
    line("ptrace", "ok (TRACEME + CONT)");
}

void probeMmapExec() {
    void *memory = mmap(nullptr, 4096, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (memory == MAP_FAILED) {
        lineErrno("mmap_exec", errno);
        return;
    }
    line("mmap_exec", "ok");
    munmap(memory, 4096);
}

/**
 * Mount namespaces hung once during the first probe run, so run this in a
 * child with a hard 3-second cap and SIGKILL it rather than blocking the
 * whole report.
 */
void probeUnshare() {
    if (!g_deep) {
        line("unshare_mount", "blocked: SIGSYS from seccomp (live test skipped)");
        return;
    }
    int pipeFd[2] = {-1, -1};
    if (pipe(pipeFd) != 0) {
        lineErrno("unshare_mount", errno);
        return;
    }
    pid_t pid = fork();
    if (pid < 0) {
        lineErrno("unshare_mount", errno);
        close(pipeFd[0]);
        close(pipeFd[1]);
        return;
    }
    if (pid == 0) {
        close(pipeFd[0]);
        int error = 0;
        if (unshare(CLONE_NEWNS) != 0) {
            error = errno;
        }
        ssize_t ignored = write(pipeFd[1], &error, sizeof(error));
        (void)ignored;
        _exit(0);
    }
    close(pipeFd[1]);
    alarm(3);
    int error = -1;
    ssize_t got = read(pipeFd[0], &error, sizeof(error));
    alarm(0);
    if (got == static_cast<ssize_t>(sizeof(error))) {
        if (error == 0) {
            line("unshare_mount", "ok");
        } else {
            lineErrno("unshare_mount", error);
        }
    } else {
        line("unshare_mount", "timeout or killed");
    }
    kill(pid, SIGKILL);
    waitpid(pid, nullptr, 0);
    close(pipeFd[0]);
}

void probeStatus() {
    FILE *status = fopen("/proc/self/status", "r");
    if (status == nullptr) {
        lineErrno("proc_status", errno);
        return;
    }
    char buffer[512];
    while (fgets(buffer, sizeof(buffer), status) != nullptr) {
        if (strncmp(buffer, "Seccomp:", 8) == 0 ||
            strncmp(buffer, "NoNewPrivs:", 11) == 0 ||
            strncmp(buffer, "CapEff:", 7) == 0) {
            char key[32];
            char value[128];
            if (sscanf(buffer, "%31[^:]: %127[^\n]", key, value) == 2) {
                line(key, value);
            }
        }
    }
    fclose(status);

    FILE *attr = fopen("/proc/self/attr/current", "r");
    if (attr != nullptr) {
        char context[256] = {0};
        if (fgets(context, sizeof(context), attr) != nullptr) {
            line("selinux_context", context);
        }
        fclose(attr);
    }
}

} // namespace

extern "C" __attribute__((visibility("default"))) void Main(NativeChildProcess_Args args) {
    char pathBuffer[1024] = {0};
    const char *path = args.entryParams;
    if (path != nullptr) {
        // "|deep" is a flag, not part of the report path.
        const char *marker = strstr(path, "|deep");
        if (marker != nullptr) {
            size_t length = static_cast<size_t>(marker - path);
            if (length >= sizeof(pathBuffer)) {
                length = sizeof(pathBuffer) - 1;
            }
            memcpy(pathBuffer, path, length);
            pathBuffer[length] = '\0';
            path = pathBuffer;
            g_deep = true;
        }
    }
    if (path != nullptr) {
        g_report = fopen(path, "w");
    }
    if (g_report == nullptr) {
        return;
    }

    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%ld", static_cast<long>(getpid()));
    line("pid", buffer);
    snprintf(buffer, sizeof(buffer), "%ld", static_cast<long>(getuid()));
    line("uid", buffer);

    struct utsname info;
    if (uname(&info) == 0) {
        snprintf(buffer, sizeof(buffer), "%s %s %s", info.sysname, info.release, info.machine);
        line("uname", buffer);
    } else {
        lineErrno("uname", errno);
    }

    if (access("/system/bin/sh", X_OK) == 0) {
        line("system_sh", "executable");
    } else {
        lineErrno("system_sh", errno);
    }

    probeSpawn("spawn_system_sh", "/system/bin/sh", "echo system-exec-ok");

    char reportDir[512] = {0};
    const char *slash = strrchr(path, '/');
    if (slash != nullptr) {
        size_t length = static_cast<size_t>(slash - path);
        if (length >= sizeof(reportDir)) {
            length = sizeof(reportDir) - 1;
        }
        memcpy(reportDir, path, length);
        reportDir[length] = '\0';
    }

    // Executable targets: the app's own native library directory is the one
    // place Android normally still allows exec from, so test it explicitly.
    char ownLib[512] = {0};
    Dl_info dlInfo;
    if (dladdr(reinterpret_cast<void *>(&Main), &dlInfo) != 0 &&
        dlInfo.dli_fname != nullptr) {
        snprintf(ownLib, sizeof(ownLib), "%s", dlInfo.dli_fname);
        line("own_lib", ownLib);

        char libDir[512];
        snprintf(libDir, sizeof(libDir), "%s", ownLib);
        char *lastSlash = strrchr(libDir, '/');
        if (lastSlash != nullptr) {
            *lastSlash = '\0';
            char candidate[640];
            snprintf(candidate, sizeof(candidate), "%s/libexecprobe.so", libDir);
            probeSpawn("libs_exec", candidate, "ignored");
        }
    }

    if (reportDir[0] != '\0') {
        if (ownLib[0] != '\0') {
            char copyPath[640];
            snprintf(copyPath, sizeof(copyPath), "%s/execprobe-copy", reportDir);
            probeFileExec(ownLib, copyPath);
        }
        probeDataExec(reportDir);
    }

    probeStatus();
    probePtrace();
    probeMmapExec();
    probeUnshare();

    line("probe", "done");
    fclose(g_report);
    g_report = nullptr;
}
