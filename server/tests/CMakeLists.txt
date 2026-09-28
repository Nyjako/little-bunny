add_executable(bunny_server_test_auth test_auth.c ../src/auth.c)
target_include_directories(bunny_server_test_auth PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(bunny_server_test_auth PRIVATE bunny_common civetweb-c-library OpenSSL::Crypto unity::framework)
add_test(NAME bunny_server_test_auth COMMAND bunny_server_test_auth)

add_executable(bunny_server_test_tls test_tls.c ../src/tls.c)
target_include_directories(bunny_server_test_tls PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_link_libraries(bunny_server_test_tls PRIVATE bunny_common OpenSSL::Crypto unity::framework)
add_test(NAME bunny_server_test_tls COMMAND bunny_server_test_tls)
