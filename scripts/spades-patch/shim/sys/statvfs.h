#pragma once
#include <sys/types.h>
struct statvfs { unsigned long f_bsize,f_frsize,f_blocks,f_bfree,f_bavail,f_files,f_ffree,f_favail,f_fsid,f_flag,f_flags,f_namemax; };
static inline int statvfs(const char* p, struct statvfs* s){ (void)p; if(s){ s->f_bsize=4096; s->f_frsize=4096; s->f_blocks=0; s->f_bfree=0; s->f_bavail=0; } return 0; }
static inline int fstatvfs(int fd, struct statvfs* s){ (void)fd; if(s){ s->f_bsize=4096; } return 0; }
