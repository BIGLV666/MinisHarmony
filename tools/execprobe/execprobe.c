/*
 * Minimal static aarch64 ELF used to test whether HarmonyOS allows an app to
 * exec a bundled executable from its native library directory or from app
 * storage. Built without libc so the binary has no interpreter and no
 * dependencies; it writes one line and exits.
 */

static long sys_write(int fd, const void *buffer, unsigned long count) {
    register long x8 __asm__("x8") = 64; /* __NR_write */
    register long x0 __asm__("x0") = fd;
    register long x1 __asm__("x1") = (long)buffer;
    register long x2 __asm__("x2") = count;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
    return x0;
}

static void sys_exit(int code) {
    register long x8 __asm__("x8") = 93; /* __NR_exit */
    register long x0 __asm__("x0") = code;
    __asm__ volatile("svc #0" : : "r"(x8), "r"(x0) : "memory");
    for (;;) {
    }
}

void _start(void) {
    static const char message[] = "exec-ok\n";
    sys_write(1, message, sizeof(message) - 1);
    sys_exit(0);
}
