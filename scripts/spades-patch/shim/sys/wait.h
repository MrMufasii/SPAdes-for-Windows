#pragma once
#include <sys/types.h>
#define WNOHANG 1
#define WIFEXITED(s) 1
#define WEXITSTATUS(s) (s)
#define WIFSIGNALED(s) 0
#define WTERMSIG(s) 0
static inline int waitpid(int pid,int* st,int o){(void)pid;(void)o; if(st)*st=0; return -1;}
