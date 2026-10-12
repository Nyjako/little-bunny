cmake_minimum_required(VERSION 3.21)
project(little-bunny C)

# Some CPM-fetched dependencies (e.g. cJSON) declare an old
# cmake_minimum_required() that CMake >= 4.0 refuses to honor. Tell CMake to
# treat those as requiring at least 3.5 rather than failing the configure.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# bunny_core_ffi/ (M6.2) links this whole project's static libs into a shared
# library for Dart FFI to dlopen. Linking a non-PIC static archive into a
# shared object fails ("recompile with -fPIC") because externally-visible
# symbols must be position-independent so other DSOs can preempt them. Set
# this globally (before any targets/CPM packages are created) rather than
# per-target, since the FFI plugin pulls in this project's entire dependency
# chain (bunny_core, bunny_db, sqlite3, curl, cJSON, ...). No-op on
# Windows/MSVC; harmless for the existing executable targets (PIE executables
# already imply PIC object code on Linux).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(BUNNY_BUILD_TESTS "Build unit tests" OFF)
option(BUNNY_ENABLE_ASAN "Build with AddressSanitizer/UndefinedBehaviorSanitizer" OFF)
option(BUNNY_BUILD_TOOLS "Build developer/experimental command-line tools (not part of the shipped product)" OFF)
option(BUNNY_BUILD_SERVER "Build the C server (civetweb, requires network to fetch). OFF for the Flutter FFI plugin's build (bunny_core_ffi/), which only needs libs/." ON)

if(BUNNY_ENABLE_ASAN)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

include(cmake/get_cpm.cmake)

# OpenSSL is the one dependency not fetched via CPM: it's treated as a system
# TLS provider (like the compiler), see docs/architecture.md. Only civetweb
# and server/src/auth.c|tls.c call into it directly, and both are already
# gated behind BUNNY_BUILD_SERVER below -- so this find_package must be too,
# otherwise it blocks every BUNNY_BUILD_SERVER=OFF consumer (bunny_core_ffi/,
# i.e. every Android build) from configuring at all, since the Android NDK
# ships no prebuilt OpenSSL (M12.1).
if(BUNNY_BUILD_SERVER)
  find_package(OpenSSL REQUIRED)
endif()

# curl (libs/common's HTTP client) needs a TLS backend regardless of
# BUNNY_BUILD_SERVER, since e621/Inkbunny API calls happen from the FFI/core
# libs too. On Android there's no prebuilt OpenSSL to use (same gap as
# above), so it gets mbedTLS instead -- a small, pure-CMake library that
# cross-compiles cleanly for the NDK via a plain CPM add_subdirectory, unlike
# OpenSSL's own Configure+make build system. Every other target keeps using
# system OpenSSL, already proven to work there.
if(ANDROID)
  CPMAddPackage(
    NAME MbedTLS
    GITHUB_REPOSITORY Mbed-TLS/mbedtls
    GIT_TAG v3.6.6
    OPTIONS
      "ENABLE_PROGRAMS OFF"
      "ENABLE_TESTING OFF"
      "USE_STATIC_MBEDTLS_LIBRARY ON"
      "USE_SHARED_MBEDTLS_LIBRARY OFF"
  )
  # curl's own CMake/FindMbedTLS.cmake module is built around discovering an
  # already-installed mbedTLS via pkg-config/CMake-config/find_library --
  # none of which apply to a CPM add_subdirectory fetch that never runs
  # install(). Whether curl's find_package(MbedTLS MODULE REQUIRED) actually
  # runs that module's own discovery logic or gets transparently redirected
  # to CPM's already-added package instead depends on the CMake version in
  # use (observed: redirected under a system CMake 4.4 install, NOT
  # redirected under the Android SDK's bundled CMake 3.22.1, which runs the
  # real module and needs its input variables satisfied) -- so satisfy both
  # paths at once: pre-set the variables FindMbedTLS.cmake's manual-discovery
  # branch checks, AND define the CURL::mbedtls target it would have created,
  # so whichever path actually executes short-circuits successfully.
  set(MBEDTLS_INCLUDE_DIR "${MbedTLS_SOURCE_DIR}/include" CACHE PATH "" FORCE)
  set(MBEDTLS_LIBRARY "${MbedTLS_BINARY_DIR}/library/libmbedtls.a" CACHE FILEPATH "" FORCE)
  set(MBEDX509_LIBRARY "${MbedTLS_BINARY_DIR}/library/libmbedx509.a" CACHE FILEPATH "" FORCE)
  set(MBEDCRYPTO_LIBRARY "${MbedTLS_BINARY_DIR}/library/libmbedcrypto.a" CACHE FILEPATH "" FORCE)
  set(MBEDTLS_VERSION "3.6.6")
  set(MBEDTLS_FOUND TRUE)
  if(NOT TARGET CURL::mbedtls)
    add_library(CURL::mbedtls INTERFACE IMPORTED)
    target_link_libraries(CURL::mbedtls INTERFACE mbedtls mbedx509 mbedcrypto)
  endif()
  set(MBEDTLS_VERSION "3.6.6")
  # The HAVE_MBEDTLS_DES_CRYPT_ECB probe runs as a try_compile() in an
  # isolated scratch project that can't see CURL::mbedtls regardless -- skip
  # it outright. curl doesn't need legacy DES for anything this app actually
  # uses (plain HTTPS GET/POST to e621/Inkbunny), so "not present" is a safe
  # answer either way.
  set(HAVE_MBEDTLS_DES_CRYPT_ECB 0 CACHE BOOL "" FORCE)
endif()

if(ANDROID)
  set(BUNNY_CURL_USE_OPENSSL OFF)
  set(BUNNY_CURL_USE_MBEDTLS ON)
else()
  set(BUNNY_CURL_USE_OPENSSL ON)
  set(BUNNY_CURL_USE_MBEDTLS OFF)
endif()

CPMAddPackage(
  NAME curl
  GITHUB_REPOSITORY curl/curl
  GIT_TAG curl-8_22_0
  OPTIONS
    "BUILD_CURL_EXE OFF"
    "BUILD_SHARED_LIBS OFF"
    "BUILD_TESTING OFF"
    "CURL_USE_OPENSSL ${BUNNY_CURL_USE_OPENSSL}"
    "CURL_USE_MBEDTLS ${BUNNY_CURL_USE_MBEDTLS}"
    "CURL_USE_LIBPSL OFF"
    "CURL_DISABLE_LDAP ON"
    "CURL_DISABLE_LDAPS ON"
    "CURL_DISABLE_TELNET ON"
    "CURL_DISABLE_DICT ON"
    "CURL_DISABLE_FILE ON"
    "CURL_DISABLE_FTP ON"
    "CURL_DISABLE_GOPHER ON"
    "CURL_DISABLE_RTSP ON"
    "CURL_DISABLE_SMTP ON"
    "CURL_DISABLE_POP3 ON"
    "CURL_DISABLE_IMAP ON"
    "CURL_DISABLE_TFTP ON"
    "CURL_DISABLE_MQTT ON"
)

CPMAddPackage(
  NAME cJSON
  GITHUB_REPOSITORY DaveGamble/cJSON
  GIT_TAG v1.7.19
  OPTIONS
    "ENABLE_CJSON_TEST OFF"
    "ENABLE_CJSON_UTILS OFF"
    "BUILD_SHARED_LIBS OFF"
)

# SQLite ships as a zip (sqlite3.c/sqlite3.h), not a CMake-ready repo, so it's
# fetched by URL and built as our own static library target.
CPMAddPackage(
  NAME sqlite3
  URL https://www.sqlite.org/2026/sqlite-amalgamation-3530400.zip
  URL_HASH SHA3_256=628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e
  DOWNLOAD_ONLY YES
)

if(sqlite3_ADDED)
  add_library(sqlite3 STATIC ${sqlite3_SOURCE_DIR}/sqlite3.c)
  target_include_directories(sqlite3 PUBLIC ${sqlite3_SOURCE_DIR})
  target_compile_definitions(sqlite3 PUBLIC
    SQLITE_DQS=0
    SQLITE_OMIT_LOAD_EXTENSION
    SQLITE_OMIT_DEPRECATED
  )
  # Android's Bionic libc has pthread built in -- there's no separate
  # libpthread to link against (NDK 28 doesn't even ship the old empty
  # compatibility stub), unlike every other non-Windows target (M12.1).
  if(ANDROID)
    target_link_libraries(sqlite3 PUBLIC m)
  elseif(NOT WIN32)
    target_link_libraries(sqlite3 PUBLIC pthread m)
  endif()
endif()

# Header-only, so no build step of its own -- just its include/ dir on an
# INTERFACE target. Pinned to a commit since GOBLIN has no tags yet.
CPMAddPackage(
  NAME GOBLIN
  GITHUB_REPOSITORY Nyjako/GOBLIN
  GIT_TAG fb4141baf198bc49f7d77da8d2d7a6e8ae7df03a
  DOWNLOAD_ONLY YES
)

if(GOBLIN_ADDED)
  add_library(goblin INTERFACE)
  target_include_directories(goblin INTERFACE ${GOBLIN_SOURCE_DIR}/include)
endif()

# M5's server embeds civetweb for HTTP/HTTPS; it links OpenSSL directly
# (no dlopen-at-runtime) since OpenSSL is already a required dependency above.
# Gated behind BUNNY_BUILD_SERVER so the Flutter FFI plugin's build
# (bunny_core_ffi/, which only needs libs/) doesn't fetch/build it at all.
if(BUNNY_BUILD_SERVER)
  CPMAddPackage(
    NAME civetweb
    GITHUB_REPOSITORY civetweb/civetweb
    GIT_TAG v1.16
    OPTIONS
      "CIVETWEB_ENABLE_CXX OFF"
      "CIVETWEB_BUILD_TESTING OFF"
      "CIVETWEB_ENABLE_SSL ON"
      "CIVETWEB_ENABLE_SSL_DYNAMIC_LOADING OFF"
      "CIVETWEB_ENABLE_ASAN OFF" # civetweb's own on-by-default-in-Debug sanitizer; our BUNNY_ENABLE_ASAN covers our own code
      "BUILD_SHARED_LIBS OFF"
  )
endif()

if(BUNNY_BUILD_TESTS)
  enable_testing()
  CPMAddPackage(
    NAME Unity
    GITHUB_REPOSITORY ThrowTheSwitch/Unity
    GIT_TAG v2.6.1
  )
endif()

add_subdirectory(libs/common)
add_subdirectory(libs/e621)
add_subdirectory(libs/inkbunny)
add_subdirectory(libs/db)
add_subdirectory(libs/core)
if(BUNNY_BUILD_SERVER)
  add_subdirectory(server)
endif()

if(BUNNY_BUILD_TOOLS)
  add_subdirectory(tools/inkbunny_favorite_experiment)
endif()
