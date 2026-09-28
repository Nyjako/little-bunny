cmake_minimum_required(VERSION 3.21)
project(little-bunny C)

# Some CPM-fetched dependencies (e.g. cJSON) declare an old
# cmake_minimum_required() that CMake >= 4.0 refuses to honor. Tell CMake to
# treat those as requiring at least 3.5 rather than failing the configure.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(BUNNY_BUILD_TESTS "Build unit tests" OFF)
option(BUNNY_ENABLE_ASAN "Build with AddressSanitizer/UndefinedBehaviorSanitizer" OFF)
option(BUNNY_BUILD_TOOLS "Build developer/experimental command-line tools (not part of the shipped product)" OFF)

if(BUNNY_ENABLE_ASAN)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

include(cmake/get_cpm.cmake)

# OpenSSL is the one dependency not fetched via CPM: it's treated as a system
# TLS provider (like the compiler), see docs/architecture.md.
find_package(OpenSSL REQUIRED)

CPMAddPackage(
  NAME curl
  GITHUB_REPOSITORY curl/curl
  GIT_TAG curl-8_22_0
  OPTIONS
    "BUILD_CURL_EXE OFF"
    "BUILD_SHARED_LIBS OFF"
    "BUILD_TESTING OFF"
    "CURL_USE_OPENSSL ON"
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
  if(NOT WIN32)
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

if(BUNNY_BUILD_TOOLS)
  add_subdirectory(tools/inkbunny_favorite_experiment)
endif()
