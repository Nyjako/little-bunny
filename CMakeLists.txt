cmake_minimum_required(VERSION 3.21)
project(little-bunny C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(BUNNY_BUILD_TESTS "Build unit tests" OFF)
option(BUNNY_ENABLE_ASAN "Build with AddressSanitizer/UndefinedBehaviorSanitizer" OFF)

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
  GIT_TAG curl-8_21_0
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
