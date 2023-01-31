#include <stdlib.h>
#include <stdio.h>

#include "zigpkg.h"

int main(int argc, char **argv) {
   (void)argc;
   printf("%d\n", zigpkg_add(atoi(argv[1])));
   printf("foo=%d bar=%d baz=%d qux=%d\n",
      zigpkg_options.foo, zigpkg_options.bar, zigpkg_options.baz, zigpkg_options.qux);
   return 0;
}
