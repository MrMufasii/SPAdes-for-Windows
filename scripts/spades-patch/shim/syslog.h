#pragma once
#include <stdarg.h>
#define LOG_EMERG 0
#define LOG_ALERT 1
#define LOG_CRIT 2
#define LOG_ERR 3
#define LOG_WARNING 4
#define LOG_NOTICE 5
#define LOG_INFO 6
#define LOG_DEBUG 7
#define LOG_PID 0
#define LOG_USER 0
static inline void openlog(const char* a,int b,int c){(void)a;(void)b;(void)c;}
static inline void closelog(void){}
static inline int setlogmask(int m){return m;}
static inline void syslog(int p,const char* f,...){(void)p;(void)f;}
static inline void vsyslog(int p,const char* f,va_list a){(void)p;(void)f;(void)a;}
