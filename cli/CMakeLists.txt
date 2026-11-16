# Everything except main() itself, so tests can link the real handshake/log
# code directly instead of spawning the built bunny_cli executable -- same
# split server/CMakeLists.txt already uses for bunny_server_lib.
add_library(bunny_cli_lib STATIC
    src/log.c
    src/handshake.c
    src/secret_prompt.c
    src/destination.c
    src/json_helpers.c
    src/rest_client.c
    src/commands.c
)

target_include_directories(bunny_cli_lib
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# rest_client.c (networked mode) talks to bunny_server directly over curl,
# with its own OpenSSL-level certificate-pinning verify callback (see its
# own doc comment on why that can't live in bunny_common/http.c instead) --
# CURL::libcurl/OpenSSL::SSL already exist in this build (bunny_common/
# server link them too), just not exported through bunny_core's PUBLIC
# interface, so they're linked here directly.
target_link_libraries(bunny_cli_lib
    PUBLIC
        bunny_core
    PRIVATE
        CURL::libcurl
        OpenSSL::SSL
        OpenSSL::Crypto
)

add_executable(bunny_cli src/main.c)
target_link_libraries(bunny_cli PRIVATE bunny_cli_lib)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
