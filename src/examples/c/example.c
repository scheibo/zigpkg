#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <zigpkg.h>

int main(int argc, char **argv)
{
   if (argc != 2) {
      fprintf(stderr, "Usage: %s <num>\n", argv[0]);
      return 1;
   }

   char *end = NULL;
   uint64_t num = strtoul(argv[1], &end, 10);
   if (errno || num > UINT32_MAX) {
      fprintf(stderr, "Invalid seed: %s\n", argv[1]);
      fprintf(stderr, "Usage: %s <seed>\n", argv[0]);
      return 1;
   }

   if (!zigpkg_compute((uint32_t *)&num)) {
      fprintf(stderr, "Result overflowed\n");
      return 1;
   }

   printf("%lu\n", num);
   return 0;
}
