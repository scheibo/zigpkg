#include <stdlib.h>
#include <stdio.h>

#include "zigpkg.h"

int main(int argc, char **argv)
{
   (void)argc;
   printf("%d\n", zigpkg_add(atoi(argv[1])));
   printf("foo=%d bar=%d baz=%d qux=%d\n",
      ZIGPKG_OPTIONS.foo, ZIGPKG_OPTIONS.bar, ZIGPKG_OPTIONS.baz, ZIGPKG_OPTIONS.qux);
   return 0;
}
