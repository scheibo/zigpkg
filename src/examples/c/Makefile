# The root Makefile passes `-p build`, but if you install to a standard system directory (eg.
# `/usr`) a lot of this setup becomes simpler (e.g. no need to mess around with the `RPATH`).
ROOT=../../../build
CFLAGS = -Wall -Wextra -pedantic -std=c99 -I$(ROOT)/include

# The windows-latest runner has a broken CC set (mingw32 doesn't support `cc`) so we specify gcc,
# though don't set it for Linux/macOS as the libraries should work with any functional C compiler.
#
# The OS won't know where to look for our dynamic libraries unless we configure the rpath to bake it
# into the executable (or set `LD_LIBRARY_PATH`, use `install_name_tool`, etc). Sadly, the flag
# requires a different syntax ($ORIGIN vs. @executable_path) for relative paths based on OS.
#
# On macOS we also need to set `-mmacosx-version-min` on our executable as Zig will set the precise
# version on the library it builds which will result in warnings as the default for the C executable
# would otherwise just be the major version.
ifeq ($(OS),Windows_NT)
	CC = gcc
else
		RPATH := -Wl,-rpath
		UNAME := $(shell uname -s)
		ifeq ($(UNAME),Linux)
				RPATH := "$(RPATH),\$$ORIGIN/$(ROOT)/lib"
		endif
		ifeq ($(UNAME),Darwin)
				RPATH := "$(RPATH),@executable_path/$(ROOT)/lib"
				CFLAGS += -mmacosx-version-min=$(shell sw_vers -productVersion)
		endif
endif

# `suffix` (to opt into libzigpkg-foo) or `static` may be set to opt into different linking
# semantics. `options` is a bit of a hack to simplify the GitHub CI as its easier than passing
# the correct suffix in the YAML
suffix ?= $(if $(findstring foo,$(options)),-foo,)
ifeq ($(static),true)
	LDFLAGS = $(ROOT)/lib/libzigpkg$(suffix).a
else
	LDFLAGS = $(RPATH) -L$(ROOT)/lib -lzigpkg$(suffix)
endif

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

example: example.o
	$(CC) -o $@ $^ $(CFLAGS) $(LDFLAGS)

.PHONY: clean
clean:
	rm -f *.o example

.DEFAULT: example
