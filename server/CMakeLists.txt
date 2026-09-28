add_executable(bunny_server
    src/main.c
    src/config.c
    src/auth.c
    src/tls.c
)

target_include_directories(bunny_server
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(bunny_server
    PRIVATE
        bunny_core
        civetweb-c-library
        OpenSSL::Crypto
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
