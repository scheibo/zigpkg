# This Makefile exists to orchestrate Zig's `build.zig` and JavaScript's `package.json`. In many
# cases you will still want to invoke `zig build` or `npm run` directly for more targeted
# execution, but to have one set of commands that covers everything, see below.

.PHONY: default
default: check

.PHONY: zig-build
zig-build:
	zig build --summary all -Dadd -p build

.PHONY: js-build
js-build: node_modules
	npm run compile

.PHONY: build
build: zig-build js-build

node_modules:
	npm install

.PHONY: install
install: node_modules

.PHONY: uninstall
uninstall:
	rm -rf node_modules

.PHONY: generate
generate:
	npm run generate

.PHONY: zig-lint
zig-lint:
	zig fmt . --check

.PHONY: js-lint
js-lint: node_modules
	npm run lint

.PHONY: lint
lint: zig-lint js-lint

.PHONY: zig-fix
zig-fix:
	zig fmt . --exclude build

.PHONY: js-fix
js-fix: node_modules
	npm run fix

.PHONY: fix
fix: zig-fix js-fix

.PHONY: zig-test
zig-test:
	zig build --summary all -Dsubtract test
	zig build --summary all -Dadd -Dsubtract test

.PHONY: js-test
js-test: js-build
	npm run test

.PHONY: test
test: zig-test js-test

.PHONY: zig-coverage
zig-coverage:
	rm -rf coverage/zig
	mkdir -p coverage/zig
	zig build --summary all test -Dtest-coverage=coverage/zig/zigpkg
	zig build --summary all -Dadd -Dsubtract test -Dtest-coverage=coverage/zig/zigpkg2
	kcov --merge coverage/zig/merged coverage/zig/zigpkg coverage/zig/zigpkg2

.PHONY: js-coverage
js-coverage: js-build
	npm run test -- --coverage

.PHONY: coverage
coverage: zig-coverage js-coverage

.PHONY: check
check: test lint

.PHONY: c-example
c-example:
	$(MAKE) -C examples/c
	./examples/c/example 40

examples/js/node_modules:
	npm -C examples/js install --install-links=false

.PHONY: js-example
js-example: examples/js/node_modules
	npm -C examples/js start -- 40

.PHONY: zig-example
zig-example:
	cd examples/zig; zig build --summary all -Dadd run -- 40

.PHONY: example
example: c-example js-example zig-example

.PHONY: integration
integration: build check example

.PHONY: clean-example
clean-example:
	$(MAKE) clean -C examples/c
	rm -rf examples/js/.parcel* examples/js/{build,dist}
	rm -rf examples/zig/zig-*

.PHONY: clean
clean: clean-example
	rm -rf zig-* build .tsbuildinfo .eslintcache

.PHONY: release
release:
	@echo "release TODO"

