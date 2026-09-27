add_library(bunny_inkbunny STATIC
    src/client.c
    src/error.c
    src/types.c
)

target_include_directories(bunny_inkbunny
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(bunny_inkbunny
    PUBLIC
        bunny_common
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
