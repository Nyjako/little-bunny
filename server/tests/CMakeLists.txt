add_executable(bunny_server_test_auth test_auth.c ../src/auth.c ../src/log.c)
target_include_directories(bunny_server_test_auth PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(bunny_server_test_auth PRIVATE bunny_common civetweb-c-library OpenSSL::Crypto unity::framework)
add_test(NAME bunny_server_test_auth COMMAND bunny_server_test_auth)

add_executable(bunny_server_test_tls test_tls.c ../src/tls.c ../src/log.c)
target_include_directories(bunny_server_test_tls PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(bunny_server_test_tls PRIVATE bunny_common OpenSSL::Crypto unity::framework)
add_test(NAME bunny_server_test_tls COMMAND bunny_server_test_tls)

add_executable(bunny_server_test_log test_log.c ../src/log.c)
target_include_directories(bunny_server_test_log PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(bunny_server_test_log PRIVATE bunny_common unity::framework)
add_test(NAME bunny_server_test_log COMMAND bunny_server_test_log)

# Starts a real bunny_server (via server_app_start(), the same code path
# main.c uses) on :memory: with a fake e621 transport, and exercises it with
# real HTTPS requests over libcurl -- no fixture can substitute for actually
# driving civetweb's request/response handling end to end.
add_executable(bunny_server_test_integration test_integration.c)
target_link_libraries(bunny_server_test_integration PRIVATE bunny_server_lib CURL::libcurl unity::framework)
if(NOT ANDROID AND NOT WIN32)
  target_link_libraries(bunny_server_test_integration PRIVATE pthread)
endif()
add_test(NAME bunny_server_test_integration COMMAND bunny_server_test_integration)
