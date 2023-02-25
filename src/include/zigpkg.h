#ifndef LIBZIGPKG_H
#define LIBZIGPKG_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

/** Compile time options set when libzigpkg was built. */
typedef struct zigpkg_options {
    bool add;
    bool subtract;
} zigpkg_options;
extern const zigpkg_options ZIGPKG_OPTIONS;

/** Computes the new value of n, returning whether or not the computation was successful. */
__attribute__((__nonnull__))
bool zigpkg_compute(uint32_t* n);

#ifdef __cplusplus
}
#endif

#endif // LIBZIGPKG_H
