add_library(bunny_db STATIC
    src/db.c
    src/error.c
    src/types.c
    src/accounts.c
    src/settings.c
    src/searches.c
    src/groups.c
    src/posts.c
    src/favorites.c
    src/votes.c
    src/blacklist.c
    src/stats.c
    src/action_queue.c
)

target_include_directories(bunny_db
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(bunny_db
    PRIVATE
        sqlite3
        # only needed for goblin_copy_cstr (see internal.h) -- bunny_db has
        # no other reason to depend on bunny_common's HTTP/JSON layer.
        bunny_common
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
