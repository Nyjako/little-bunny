add_library(bunny_db STATIC
    src/db.c
    src/error.c
    src/types.c
    src/searches.c
    src/posts.c
    src/favorites.c
    src/downloads.c
    src/stats.c
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
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
