add_library(bunny_core STATIC
    src/core.c
    src/error.c
    src/accounts.c
    src/searches.c
    src/site_clients.c
    src/sync.c
    src/queue.c
)

target_include_directories(bunny_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(bunny_core
    PUBLIC
        bunny_db
        bunny_common
    PRIVATE
        bunny_e621
        bunny_inkbunny
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
