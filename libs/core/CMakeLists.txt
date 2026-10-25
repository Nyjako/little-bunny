add_library(bunny_core STATIC
    src/core.c
    src/error.c
    src/accounts.c
    src/searches.c
    src/site_clients.c
    src/sync.c
    src/queue.c
    src/verify.c
    src/blacklist.c
    src/backup.c
    src/stats_report.c
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

# bunny_db links sqlite3 PRIVATE, so pthread doesn't propagate transitively
# here even though sqlite3 itself links it -- bunny_core's own db_mutex
# (internal.h) needs it directly. Same ANDROID/WIN32 conditional already
# used for the sqlite3 target in the top-level CMakeLists.txt.
if(ANDROID)
  # Bionic libc has pthread built in -- nothing to link.
elseif(NOT WIN32)
  target_link_libraries(bunny_core PRIVATE pthread)
endif()

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
