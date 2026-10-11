# Everything except main() itself, so tests can link the real server and
# drive it via server_app_start()/server_app_stop() (server/src/app.h)
# instead of spawning the built executable as a subprocess.
add_library(bunny_server_lib STATIC
    src/app.c
    src/config.c
    src/auth.c
    src/tls.c
    src/scheduler.c
    src/route_utils.c
    src/json_helpers.c
    src/routes_accounts.c
    src/routes_searches.c
    src/routes_queue.c
    src/routes_tags.c
    src/routes_pools.c
    src/routes_search.c
    src/routes_blacklist.c
)

target_include_directories(bunny_server_lib
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(bunny_server_lib
    PUBLIC
        bunny_core
        civetweb-c-library
        OpenSSL::Crypto
)

add_executable(bunny_server src/main.c)
target_link_libraries(bunny_server PRIVATE bunny_server_lib)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
