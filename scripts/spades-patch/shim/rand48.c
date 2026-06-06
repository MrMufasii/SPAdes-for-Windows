#include <stdlib.h>
#include <io.h>
double drand48(void){ return (double)rand()/((double)RAND_MAX+1.0); }
long   lrand48(void){ return rand(); }
void   srand48(long s){ srand((unsigned)s); }
int    fsync(int fd){ return _commit(fd); }
