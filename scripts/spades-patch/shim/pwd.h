#pragma once
#include <sys/types.h>
struct passwd { char* pw_name; char* pw_dir; int pw_uid; int pw_gid; };
static inline struct passwd* getpwuid(int u){ (void)u; return 0; }
static inline struct passwd* getpwnam(const char* n){ (void)n; return 0; }
