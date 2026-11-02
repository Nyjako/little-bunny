add_library(bunny_tag_query STATIC
    src/tag_query.c
)

target_include_directories(bunny_tag_query
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(bunny_tag_query
    PRIVATE
        # GOBLIN_DYN_ARRAY_DECL only -- no I/O, no other bunny_* dependency.
        goblin
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
