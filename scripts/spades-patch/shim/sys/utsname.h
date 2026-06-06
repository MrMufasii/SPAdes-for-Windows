#pragma once
#include <string.h>
struct utsname { char sysname[65]; char nodename[65]; char release[65]; char version[65]; char machine[65]; };
static inline int uname(struct utsname* u){ if(u){ memset(u,0,sizeof(*u)); strcpy(u->sysname,"Windows"); strcpy(u->machine,"x86_64"); } return 0; }
