/* Minimal POSIX <sys/resource.h> shim for MinGW. Resource limits are not
   enforced on Windows; getrlimit reports "unlimited", setrlimit is a no-op,
   and getrusage returns zeros (only used for timing/logging in SPAdes). */
#ifndef SHIM_SYS_RESOURCE_H
#define SHIM_SYS_RESOURCE_H

#include <sys/time.h>
#include <stdint.h>

#define RLIMIT_CPU    0
#define RLIMIT_FSIZE  1
#define RLIMIT_DATA   2
#define RLIMIT_STACK  3
#define RLIMIT_CORE   4
#define RLIMIT_NOFILE 5
#define RLIMIT_AS     6
#define RLIMIT_RSS    7
#define RLIM_INFINITY (~(rlim_t)0)

typedef uint64_t rlim_t;
struct rlimit { rlim_t rlim_cur; rlim_t rlim_max; };

#define RUSAGE_SELF     0
#define RUSAGE_CHILDREN (-1)
struct rusage {
    struct timeval ru_utime;
    struct timeval ru_stime;
    long ru_maxrss;
    long ru_minflt;
    long ru_majflt;
    long ru_nvcsw;
    long ru_nivcsw;
};

#ifdef __cplusplus
extern "C" {
#endif

static inline int getrlimit(int resource, struct rlimit *rl) {
    (void)resource;
    if (rl) { rl->rlim_cur = RLIM_INFINITY; rl->rlim_max = RLIM_INFINITY; }
    return 0;
}
static inline int setrlimit(int resource, const struct rlimit *rl) {
    (void)resource; (void)rl; return 0;
}
static inline int getrusage(int who, struct rusage *r) {
    (void)who;
    if (r) {
        r->ru_utime.tv_sec = 0; r->ru_utime.tv_usec = 0;
        r->ru_stime.tv_sec = 0; r->ru_stime.tv_usec = 0;
        r->ru_maxrss = 0; r->ru_minflt = 0; r->ru_majflt = 0;
        r->ru_nvcsw = 0; r->ru_nivcsw = 0;
    }
    return 0;
}

#ifdef __cplusplus
}
#endif

#endif /* SHIM_SYS_RESOURCE_H */
