#ifndef LIBZIGPKG_H
#define LIBZIGPKG_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

typedef struct zigpkg_options_type {
    bool foo;
    bool bar;
    bool baz;
    bool qux;
} zigpkg_options_type;

extern const zigpkg_options_type zigpkg_options;

uint8_t zigpkg_add(uint8_t n);

#ifdef __cplusplus
}
#endif

#endif // LIBZIGPKG_H
