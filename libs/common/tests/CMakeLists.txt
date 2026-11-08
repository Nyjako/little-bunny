add_executable(bunny_common_test_md5 test_md5.c)
target_link_libraries(bunny_common_test_md5 PRIVATE bunny_common unity::framework)
add_test(NAME bunny_common_test_md5 COMMAND bunny_common_test_md5)

# A tiny local-only HTTP responder for tests that need a real URL to fetch
# from -- this project's own vendored curl has CURL_DISABLE_FILE ON, so
# file:// URLs aren't an option (see test_http_server.h). A STATIC library
# (not just extra sources on one test target) since libs/core/tests' own
# download test (M66) needs the exact same server.
add_library(bunny_test_http_server STATIC test_http_server.c)
target_link_libraries(bunny_test_http_server PUBLIC bunny_common)
if(NOT ANDROID AND NOT WIN32)
    target_link_libraries(bunny_test_http_server PUBLIC pthread)
endif()

add_executable(bunny_common_test_download test_download.c)
target_link_libraries(bunny_common_test_download PRIVATE bunny_common bunny_test_http_server unity::framework)
add_test(NAME bunny_common_test_download COMMAND bunny_common_test_download)
