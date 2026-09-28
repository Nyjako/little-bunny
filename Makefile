BUILD_DIR ?= build
RELEASE_DIR ?= build-release
WINDOWS_DIR ?= build-windows
TOOLS_DIR ?= build-tools

SOURCES := $(shell find libs tools -name '*.c' -o -name '*.h')

.PHONY: build test release clean dockcross windows tools format format-check

build:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Debug -DBUNNY_BUILD_TESTS=ON
	cmake --build $(BUILD_DIR) -j

test: build
	ctest --test-dir $(BUILD_DIR) --output-on-failure

release:
	cmake -S . -B $(RELEASE_DIR) -DCMAKE_BUILD_TYPE=Release -DBUNNY_BUILD_TESTS=OFF
	cmake --build $(RELEASE_DIR) -j

clean:
	rm -rf $(BUILD_DIR) $(RELEASE_DIR) $(WINDOWS_DIR) $(TOOLS_DIR)

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
