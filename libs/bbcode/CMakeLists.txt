add_library(bunny_bbcode STATIC
    src/bbcode.c
)

target_include_directories(bunny_bbcode
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(bunny_bbcode
    PUBLIC
        # bunny_common/doc.h is the shared document model this parser
        # produces (bunny_doc_t) and bunny_doc_free lives there.
        bunny_common
    PRIVATE
        goblin
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
