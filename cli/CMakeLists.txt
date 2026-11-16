# Everything except main() itself, so tests can link the real handshake/log
# code directly instead of spawning the built bunny_cli executable -- same
# split server/CMakeLists.txt already uses for bunny_server_lib.
add_library(bunny_cli_lib STATIC
    src/log.c
    src/handshake.c
    src/secret_prompt.c
)

target_include_directories(bunny_cli_lib
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(bunny_cli_lib
    PUBLIC
        bunny_core
)

add_executable(bunny_cli src/main.c)
target_link_libraries(bunny_cli PRIVATE bunny_cli_lib)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
