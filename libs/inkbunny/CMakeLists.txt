add_library(bunny_inkbunny STATIC
    src/client.c
    src/error.c
    src/types.c
    src/unofficial_favorites.c
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
    PRIVATE
        # unofficial_favorites.c needs its own persistent CURL handle
        # (cookie-jar session), unlike the rest of this library which only
        # goes through bunny_common's injectable transport.
        CURL::libcurl
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
