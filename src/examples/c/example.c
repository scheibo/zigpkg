#include <errno.h>
#include <stdlib.h>
#include <stdio.h>

#include <zigpkg.h>

int main(int argc, char **argv)
{
   if (argc != 2) {
      fprintf(stderr, "Usage: %s <num>\n", argv[0]);
      return 1;
   }

   char *end = NULL;
   uint64_t num = strtoul(argv[1], &end, 10);
   if (errno || num > 255) {
      fprintf(stderr, "Invalid seed: %s\n", argv[1]);
      fprintf(stderr, "Usage: %s <seed>\n", argv[0]);
      return 1;
   }

   printf("%d\n", zigpkg_add((uint8_t)num));
   return 0;
}
