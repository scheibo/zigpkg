#ifndef LIBZIGPKG_H
#define LIBZIGPKG_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

/** Compile time options set when libzigpkg was built. */
typedef struct zigpkg_options {
    bool foo;
    bool bar;
    bool baz;
    bool qux;
} zigpkg_options;
extern const zigpkg_options ZIGPKG_OPTIONS;

/** Adds to n and returns the result. */
uint8_t zigpkg_add(uint8_t n);

#ifdef __cplusplus
}
#endif

#endif // LIBZIGPKG_H
