#pragma once
/* POSIX glob(3) shim for MinGW, backed by Win32 FindFirstFile.
   FindFirstFile globs the LAST path component with * and ? — which covers
   SPAdes' dataset wildcard usage (e.g. /path/to/*_R1.fastq.gz). The directory
   portion is taken literally and prepended to each match. A pattern with no
   wildcard resolves to itself iff the file exists (matching glob's behaviour). */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

typedef struct { size_t gl_pathc; char** gl_pathv; size_t gl_offs; } glob_t;

#define GLOB_ERR      0x0001
#define GLOB_MARK     0x0008
#define GLOB_NOSORT   0x0020
#define GLOB_NOESCAPE 0x2000
#define GLOB_NOSPACE  1
#define GLOB_ABORTED  2
#define GLOB_NOMATCH  3

#ifdef __cplusplus
extern "C" {
#endif

static inline int glob(const char* pattern, int flags,
                       int (*errfunc)(const char*, int), glob_t* g) {
    (void)flags; (void)errfunc;
    if (g) { g->gl_pathc = 0; g->gl_pathv = 0; g->gl_offs = 0; }

    /* split off the directory prefix (kept literally) */
    const char* slash = strrchr(pattern, '/');
    const char* bslash = strrchr(pattern, '\\');
    const char* sep = slash > bslash ? slash : bslash;
    size_t dirlen = sep ? (size_t)(sep - pattern + 1) : 0;

    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE)
        return GLOB_NOMATCH;

    size_t cap = 16, n = 0;
    char** v = (char**)malloc(cap * sizeof(char*));
    if (!v) { FindClose(h); return GLOB_NOSPACE; }

    do {
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0)
            continue;
        if (n + 1 >= cap) {
            cap *= 2;
            char** nv = (char**)realloc(v, cap * sizeof(char*));
            if (!nv) { break; }
            v = nv;
        }
        size_t namelen = strlen(fd.cFileName);
        char* full = (char*)malloc(dirlen + namelen + 1);
        if (!full) break;
        if (dirlen) memcpy(full, pattern, dirlen);
        memcpy(full + dirlen, fd.cFileName, namelen + 1);
        v[n++] = full;
    } while (FindNextFileA(h, &fd));
    FindClose(h);

    if (n == 0) { free(v); return GLOB_NOMATCH; }
    v[n] = NULL;
    if (g) { g->gl_pathc = n; g->gl_pathv = v; g->gl_offs = 0; }
    return 0;
}

static inline void globfree(glob_t* g) {
    if (!g || !g->gl_pathv) return;
    for (size_t i = 0; i < g->gl_pathc; ++i) free(g->gl_pathv[i]);
    free(g->gl_pathv);
    g->gl_pathv = 0; g->gl_pathc = 0;
}

#ifdef __cplusplus
}
#endif
