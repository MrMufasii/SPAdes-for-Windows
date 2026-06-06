/* Windows implementation of the POSIX mmap family (mman-win32 style). */
#include "sys/mman.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <io.h>
#include <errno.h>

static DWORD prot_to_page(int prot) {
    if (prot == PROT_NONE) return 0;
    if (prot & PROT_EXEC)
        return (prot & PROT_WRITE) ? PAGE_EXECUTE_READWRITE : PAGE_EXECUTE_READ;
    return (prot & PROT_WRITE) ? PAGE_READWRITE : PAGE_READONLY;
}

static DWORD prot_to_access(int prot) {
    DWORD a = 0;
    if (prot == PROT_NONE) return 0;
    if (prot & PROT_WRITE) a = FILE_MAP_WRITE;   /* implies read on Windows */
    else if (prot & PROT_READ) a = FILE_MAP_READ;
    if (prot & PROT_EXEC) a |= FILE_MAP_EXECUTE;
    return a;
}

/* Map a Win32 error to a POSIX errno so strerror() is meaningful in logs. */
static void set_errno_from_win(void) {
    DWORD e = GetLastError();
    switch (e) {
        case ERROR_ACCESS_DENIED:      errno = EACCES; break;
        case ERROR_INVALID_HANDLE:     errno = EBADF;  break;
        case ERROR_NOT_ENOUGH_MEMORY:
        case ERROR_OUTOFMEMORY:        errno = ENOMEM; break;
        case ERROR_INVALID_ADDRESS:
        case ERROR_MAPPED_ALIGNMENT:   errno = EINVAL; break;
        default:                       errno = EACCES; break;
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    HANDLE fh, mh;
    void *map;
    static DWORD gran = 0;
    unsigned long long uoff, aligned, maxsize;
    size_t diff;
    (void)addr;
    if (length == 0) { errno = EINVAL; return MAP_FAILED; }

    if (!gran) { SYSTEM_INFO si; GetSystemInfo(&si); gran = si.dwAllocationGranularity; }

    if ((flags & MAP_ANONYMOUS) || fd == -1)
        fh = INVALID_HANDLE_VALUE;
    else {
        fh = (HANDLE)_get_osfhandle(fd);
        if (fh == INVALID_HANDLE_VALUE) { errno = EBADF; return MAP_FAILED; }
    }

    /* MapViewOfFile requires the file offset to be a multiple of the allocation
       granularity (64 KB), but POSIX callers only align to the page size (4 KB).
       Round the offset down to a granularity boundary, map the extra bytes, and
       hand back a pointer shifted by the difference. munmap() rounds back down. */
    uoff = (unsigned long long)offset;
    aligned = uoff & ~((unsigned long long)gran - 1ULL);
    diff = (size_t)(uoff - aligned);
    maxsize = uoff + (unsigned long long)length;   /* end of region within the file */

    mh = CreateFileMappingA(fh, NULL, prot_to_page(prot),
                            (DWORD)(maxsize >> 32), (DWORD)(maxsize & 0xFFFFFFFFu), NULL);
    if (mh == NULL) { set_errno_from_win(); return MAP_FAILED; }

    map = MapViewOfFile(mh, prot_to_access(prot),
                        (DWORD)(aligned >> 32), (DWORD)(aligned & 0xFFFFFFFFu),
                        length + diff);
    CloseHandle(mh);
    if (map == NULL) { set_errno_from_win(); return MAP_FAILED; }
    return (char *)map + diff;
}

int munmap(void *addr, size_t length) {
    static DWORD gran = 0;
    uintptr_t base;
    (void)length;
    if (!gran) { SYSTEM_INFO si; GetSystemInfo(&si); gran = si.dwAllocationGranularity; }
    /* mmap() returned base+diff; the MapViewOfFile base is that pointer rounded
       down to the allocation granularity (diff < gran). */
    base = (uintptr_t)addr & ~((uintptr_t)gran - 1ULL);
    return UnmapViewOfFile((void *)base) ? 0 : -1;
}

int mprotect(void *addr, size_t length, int prot) {
    DWORD old;
    return VirtualProtect(addr, length, prot_to_page(prot), &old) ? 0 : -1;
}

int msync(void *addr, size_t length, int flags) {
    (void)flags;
    return FlushViewOfFile(addr, length) ? 0 : -1;
}

int madvise(void *addr, size_t length, int advice) {
    (void)addr; (void)length; (void)advice;
    return 0;
}

int posix_madvise(void *addr, size_t length, int advice) {
    return madvise(addr, length, advice);
}

/* Shared-memory stubs: only referenced by the standalone bwa executable's
   shared-index feature, which SPAdes isolate assembly does not use. */
int shm_open(const char *name, int oflag, int mode) {
    (void)name; (void)oflag; (void)mode; errno = ENOSYS; return -1;
}
int shm_unlink(const char *name) {
    (void)name; errno = ENOSYS; return -1;
}
