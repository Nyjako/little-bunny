BUILD_DIR ?= build
RELEASE_DIR ?= build-release
PORTABLE_DIR ?= build-release-portable
WINDOWS_DIR ?= build-windows
TOOLS_DIR ?= build-tools
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

.PHONY: build test release release-portable clean dockcross windows tools format format-check app-linux app-android

build:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Debug -DBUNNY_BUILD_TESTS=ON
	cmake --build $(BUILD_DIR) -j

test: build
	ctest --test-dir $(BUILD_DIR) --output-on-failure

release:
	cmake -S . -B $(RELEASE_DIR) -DCMAKE_BUILD_TYPE=Release -DBUNNY_BUILD_TESTS=OFF
	cmake --build $(RELEASE_DIR) -j

# Use this (not plain `release`) when building on one machine to deploy onto
# another (deploy/install-prebuilt.sh's use case) -- see the PORTABLE_IMAGE
# comment above for why. Requires Docker; the host's own compiler/CMake/
# OpenSSL are never used. Output lands in $(PORTABLE_DIR)/server/bunny_server,
# owned by the invoking user (not root) despite the build running as root
# inside the container, since apt-get needs it.
release-portable:
	docker run --rm -v $(CURDIR):/src -w /src $(PORTABLE_IMAGE) bash -c "\
		apt-get update -qq && \
		apt-get install -y --no-install-recommends build-essential cmake libssl-dev ca-certificates git && \
		cmake -S . -B $(PORTABLE_DIR) -DCMAKE_BUILD_TYPE=Release -DBUNNY_BUILD_TESTS=OFF && \
		cmake --build $(PORTABLE_DIR) -j && \
		chown -R $(HOST_UID):$(HOST_GID) $(PORTABLE_DIR)"

clean:
	rm -rf $(BUILD_DIR) $(RELEASE_DIR) $(PORTABLE_DIR) $(WINDOWS_DIR) $(TOOLS_DIR)

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
