ROOT=../../../zig-out

ifneq ($(OS),Windows_NT)
		RPATH := -Wl,-rpath
		UNAME := $(shell uname -s)
		ifeq ($(UNAME),Linux)
				RPATH := $(RPATH),$$ORIGIN/$(ROOT)/lib
		endif
		ifeq ($(UNAME),Darwin)
				RPATH := "$(RPATH),@executable_path/$(ROOT)/lib"
		endif
endif

CFLAGS=-Wall -Wextra -pedantic -std=c99 -I$(ROOT)/include

ifeq ($(static),true)
	LDFLAGS := $(ROOT)/lib/libzigpkg$(suffix).a
else
	LDFLAGS := $(RPATH) -L$(ROOT)/lib -lzigpkg$(suffix)
endif

%.o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

example: example.o
	$(CC) -o $@ $^ $(CFLAGS) $(LDFLAGS)

.PHONY: clean
clean:
	rm -f *.o example

.DEFAULT: example

