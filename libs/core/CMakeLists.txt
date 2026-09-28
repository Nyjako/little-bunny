add_library(bunny_core STATIC
    src/core.c
    src/error.c
    src/accounts.c
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
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
