/* Minimal POSIX <sys/mman.h> shim for building POSIX C/C++ on MinGW (Windows).
   mmap/munmap/mprotect/msync are real (CreateFileMapping/MapViewOfFile);
   madvise is a no-op; shm_open/shm_unlink are stubs (unused by the linked libs). */
#ifndef SHIM_SYS_MMAN_H
#define SHIM_SYS_MMAN_H

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PROT_NONE  0x0
#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define PROT_EXEC  0x4

#define MAP_FILE      0x00
#define MAP_SHARED    0x01
#define MAP_PRIVATE   0x02
#define MAP_TYPE      0x0f
#define MAP_FIXED     0x10
#define MAP_ANONYMOUS 0x20
#define MAP_ANON      MAP_ANONYMOUS
#define MAP_FAILED    ((void *)-1)

#define MS_ASYNC      0x1
#define MS_SYNC       0x2
#define MS_INVALIDATE 0x4

#define MADV_NORMAL     0
#define MADV_RANDOM     1
#define MADV_SEQUENTIAL 2
#define MADV_WILLNEED   3
#define MADV_DONTNEED   4
#define POSIX_MADV_NORMAL     MADV_NORMAL
#define POSIX_MADV_RANDOM     MADV_RANDOM
#define POSIX_MADV_SEQUENTIAL MADV_SEQUENTIAL
#define POSIX_MADV_WILLNEED   MADV_WILLNEED
#define POSIX_MADV_DONTNEED   MADV_DONTNEED

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int   munmap(void *addr, size_t length);
int   mprotect(void *addr, size_t length, int prot);
int   msync(void *addr, size_t length, int flags);
int   madvise(void *addr, size_t length, int advice);
int   posix_madvise(void *addr, size_t length, int advice);
int   shm_open(const char *name, int oflag, int mode);
int   shm_unlink(const char *name);

#ifdef __cplusplus
}
#endif

#endif /* SHIM_SYS_MMAN_H */
