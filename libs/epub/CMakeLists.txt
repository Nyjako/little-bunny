add_library(bunny_epub STATIC
    src/zip.c
    src/epub.c
)

target_include_directories(bunny_epub
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(bunny_epub
    PUBLIC
        # bunny_common/doc.h is the shared document model this library
        # reads/writes (bunny_doc_t) and bunny_doc_free lives there.
        bunny_common
)

if(BUNNY_BUILD_TESTS)
    add_subdirectory(tests)
endif()
