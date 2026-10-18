BUILD_DIR ?= build
RELEASE_DIR ?= build-release
PORTABLE_DIR ?= build-release-portable
WINDOWS_DIR ?= build-windows
TOOLS_DIR ?= build-tools
APP_BUILD_DIR ?= app/build
FFI_BUILD_DIR ?= bunny_core_ffi/build
# glibc/OpenSSL symbol versions are forward-compatible only -- a binary built
# against a newer glibc/OpenSSL than the deploy target has won't run there
# (see "error while loading shared libraries: ... version `GLIBC_2.xx' not
# found"). Ubuntu 22.04's glibc (2.35) and OpenSSL (3.0.x) are old enough to
# cover virtually every currently-supported Ubuntu/Debian server release
# while still being OpenSSL 3.x (the same SONAME family every current distro
# ships), so building inside that container is the portable baseline for
# release-portable below.
PORTABLE_IMAGE ?= ubuntu:22.04
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

.PHONY: build test test-c test-flutter release release-portable clean dockcross windows tools format format-check app-linux app-android

build:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Debug -DBUNNY_BUILD_TESTS=ON
	cmake --build $(BUILD_DIR) -j

# Everything: the C side (libs/server) plus bunny_core_ffi's and the Flutter
# app's own test suites, same split test.yml runs in CI. `test-c`/
# `test-flutter` are also available standalone, for a faster loop when only
# one side actually changed.
test: test-c test-flutter

test-c: build
	ctest --test-dir $(BUILD_DIR) --output-on-failure

# Assumes Flutter (via fvm, pinned by app/.fvmrc) and the Linux desktop build
# deps (ninja-build libgtk-3-dev pkg-config libsecret-1-dev) are already
# installed -- same assumption `build`/`test-c` make about the C toolchain,
# never auto-installed by this Makefile either. Both bunny_core_ffi's and
# app's own FFI-backed tests dlopen libbunny_core_ffi.so at runtime (Dart
# FFI's DynamicLibrary.open searches LD_LIBRARY_PATH), so it has to be built
# fresh before either `flutter test` call -- `flutter build linux --debug`
# builds it as a side effect of building the app itself.
test-flutter:
	cd bunny_core_ffi && fvm flutter pub get
	cd app && fvm flutter pub get
	cd app && fvm flutter build linux --debug
	cd bunny_core_ffi && LD_LIBRARY_PATH=$(CURDIR)/$(APP_BUILD_DIR)/linux/x64/debug/bundle/lib fvm flutter test
	cd app && LD_LIBRARY_PATH=$(CURDIR)/$(APP_BUILD_DIR)/linux/x64/debug/bundle/lib fvm flutter test

release:
	cmake -S . -B $(RELEASE_DIR) -DCMAKE_BUILD_TYPE=Release -DBUNNY_BUILD_TESTS=OFF
	cmake --build $(RELEASE_DIR) -j

# Use this (not plain `release`) when building on one machine to deploy onto
# another (deploy/install-prebuilt.sh's use case) -- see the PORTABLE_IMAGE
# comment above for why. Requires Docker; the host's own compiler/CMake/
# OpenSSL are never used. Output lands in $(PORTABLE_DIR)/server/bunny_server,
# owned by the invoking user (not root) despite the build running as root
# inside the container, since apt-get needs it.
#
# The chown is in a trap, not chained with `&&` after the build -- a `&&`
# chain only runs it after every earlier step succeeds, so any failure
# (a transient apt-get/network blip, a real build error, etc.) skipped it
# and left $(PORTABLE_DIR) root-owned on disk, which then needed `sudo rm -rf`
# to remove (plain non-root `rm -rf`/`make clean` can't delete a directory
# it doesn't have write permission into) and made the next `release-portable`
# run fail too. `trap ... EXIT` always fires, success or failure, so
# ownership is fixed either way; `|| true` only guards the case where
# $(PORTABLE_DIR) doesn't exist yet at all (e.g. apt-get itself failed).
release-portable:
	docker run --rm -v $(CURDIR):/src -w /src $(PORTABLE_IMAGE) bash -c "\
		trap 'chown -R $(HOST_UID):$(HOST_GID) $(PORTABLE_DIR) 2>/dev/null || true' EXIT; \
		apt-get update -qq && \
		apt-get install -y --no-install-recommends build-essential cmake libssl-dev ca-certificates git && \
		cmake -S . -B $(PORTABLE_DIR) -DCMAKE_BUILD_TYPE=Release -DBUNNY_BUILD_TESTS=OFF && \
		cmake --build $(PORTABLE_DIR) -j"

# Also removes app/ and bunny_core_ffi/'s own build output -- app-linux/
# app-android (below) are this Makefile's own wrappers for building the
# Flutter app, so this is the one clean target that should take care of
# everything `make` itself can produce, not just the C side.
clean:
	rm -rf $(BUILD_DIR) $(RELEASE_DIR) $(PORTABLE_DIR) $(WINDOWS_DIR) $(TOOLS_DIR) $(APP_BUILD_DIR) $(FFI_BUILD_DIR)

tools:
	cmake -S . -B $(TOOLS_DIR) -DCMAKE_BUILD_TYPE=Debug -DBUNNY_BUILD_TOOLS=ON
	cmake --build $(TOOLS_DIR) -j

dockcross:
	docker run --rm dockcross/windows-static-x64 > ./dockcross
	chmod +x ./dockcross

windows: dockcross
	./dockcross cmake -S . -B $(WINDOWS_DIR) -DCMAKE_BUILD_TYPE=Release -DBUNNY_BUILD_TESTS=OFF
	./dockcross cmake --build $(WINDOWS_DIR) -j

format:
	clang-format -i $(SOURCES)

format-check:
	clang-format --dry-run --Werror $(SOURCES)

app-linux:
	cd app && fvm flutter build linux

app-android:
	cd app && fvm flutter build apk
