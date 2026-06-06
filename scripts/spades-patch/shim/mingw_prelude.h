/* Force-included into every SPAdes TU on MinGW: supplies POSIX types/functions
   MinGW lacks, so the (LLVM_ON_UNIX) code paths compile. Stubs where behaviour
   is non-essential (signals/resource ids); real where it matters (mmap comes
   from the sys/mman.h shim). */
#ifndef MINGW_PRELUDE_H
#define MINGW_PRELUDE_H
#ifdef _WIN32

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <signal.h>
#include <sys/mman.h>   /* shim: real CreateFileMapping-based mmap */

typedef int uid_t;
typedef int gid_t;
typedef unsigned short nlink_t;
typedef unsigned int uint;

/* rand48 + fsync are DEFINED in libposixshim.a (declared here). Avoids colliding
   with samtools' own _WIN32 drand48 and pulling <io.h> (which clashes with
   nlopt's local close()). */
double drand48(void);
long   lrand48(void);
void   srand48(long);
int    fsync(int);
static inline char *ctime_r(const time_t *t, char *b) { char *s = ctime(t); if (s) strncpy(b, s, 26); return b; }
static inline int getuid(void)  { return 0; }
static inline int geteuid(void) { return 0; }
static inline int getgid(void)  { return 0; }
static inline int getegid(void) { return 0; }
static inline int getppid(void) { return 0; }

/* random(3): SPAdes only ever calls srandom(42) for deterministic seeding;
   map onto the C rand() family. sync(2): flush fs buffers — no-op on Windows
   (the OS flushes lazily; SPAdes calls it only as a best-effort barrier). */
static inline void srandom(unsigned s) { srand(s); }
static inline long random(void) { return rand(); }
static inline void sync(void) { }

/* signals: enough to compile LLVM's Unix crash handler (no-op stubs) */
#ifndef SIGPIPE
#define SIGPIPE 13
#endif
#ifndef SIGBUS
#define SIGBUS 7
#endif
#ifndef SIGTRAP
#define SIGTRAP 5
#endif
#ifndef SIGQUIT
#define SIGQUIT 3
#endif
#ifndef SIGKILL
#define SIGKILL 9
#endif
#ifndef SIGHUP
#define SIGHUP 1
#endif
#ifndef SIG_BLOCK
#define SIG_BLOCK 0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2
#endif
typedef int sigset_t;
struct sigaction { void (*sa_handler)(int); int sa_flags; sigset_t sa_mask; };
static inline int sigemptyset(sigset_t *s) { if (s) *s = 0; return 0; }
static inline int sigfillset(sigset_t *s) { if (s) *s = ~0; return 0; }
static inline int sigaddset(sigset_t *s, int n) { (void)n; if (s) *s |= 1; return 0; }
static inline int sigdelset(sigset_t *s, int n) { (void)s; (void)n; return 0; }
static inline int sigprocmask(int how, const sigset_t *s, sigset_t *o) { (void)how; (void)s; if (o) *o = 0; return 0; }
static inline int sigaction(int sig, const struct sigaction *a, struct sigaction *o) {
    (void)sig; (void)a; if (o) { o->sa_handler = 0; o->sa_flags = 0; o->sa_mask = 0; } return 0;
}

/* page size + process/exec stubs (LLVM Program.inc Unix path needs only to
   compile; SPAdes spawns subprocesses via Python, not llvm::ExecuteAndWait) */
static inline int getpagesize(void) { return 4096; }
static inline int fork(void) { return -1; }
static inline unsigned alarm(unsigned s) { (void)s; return 0; }
static inline int kill(int p, int s) { (void)p; (void)s; return 0; }
static inline int wait(int *st) { if (st) *st = 0; return -1; }
static inline const char *strsignal(int s) { (void)s; return "signal"; }

#ifndef SIGALRM
#define SIGALRM 14
#endif
#ifndef SIGUSR1
#define SIGUSR1 10
#endif
#ifndef SIGUSR2
#define SIGUSR2 12
#endif
#ifndef SA_NODEFER
#define SA_NODEFER   0x40000000
#endif
#ifndef SA_RESETHAND
#define SA_RESETHAND 0x80000000
#endif
#ifndef SA_ONSTACK
#define SA_ONSTACK   0x08000000
#endif
#ifndef SA_SIGINFO
#define SA_SIGINFO   0x00000004
#endif
#ifndef _SC_PAGESIZE
#define _SC_PAGESIZE 1
#endif
#ifndef _SC_PAGE_SIZE
#define _SC_PAGE_SIZE 1
#endif
#ifndef _SC_NPROCESSORS_ONLN
#define _SC_NPROCESSORS_ONLN 2
#endif
#ifndef _SC_ARG_MAX
#define _SC_ARG_MAX 3
#endif
#ifndef _POSIX_ARG_MAX
#define _POSIX_ARG_MAX 4096
#endif
static inline long sysconf(int name) {
    switch (name) { case 1: return 4096; case 2: return 1; case 3: return 131072; default: return -1; }
}

/* NOTE: LLVM Path.inc's POSIX fs ops (readlink/realpath/symlink/link) and the
   file_t (int vs void*) handling are patched LOCALLY in Path.inc, NOT here —
   defining them globally leaked into libstdc++ <fstream> and broke it. */

#endif /* _WIN32 */
#endif /* MINGW_PRELUDE_H */
