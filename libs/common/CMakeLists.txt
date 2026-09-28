add_library(bunny_common STATIC
    src/http.c
    src/json.c
    src/goblin_impl.c
)

target_include_directories(bunny_common
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${cJSON_SOURCE_DIR}
)

target_link_libraries(bunny_common
    PUBLIC
        cjson
        goblin
    PRIVATE
        CURL::libcurl
)
