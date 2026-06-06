#pragma once
#include <stddef.h>
static inline int backtrace(void** b,int s){(void)b;(void)s; return 0;}
static inline char** backtrace_symbols(void* const* b,int s){(void)b;(void)s; return 0;}
static inline void backtrace_symbols_fd(void* const* b,int s,int fd){(void)b;(void)s;(void)fd;}
