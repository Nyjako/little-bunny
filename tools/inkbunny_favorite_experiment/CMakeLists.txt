add_executable(inkbunny_favorite_experiment main.c)

target_include_directories(inkbunny_favorite_experiment PRIVATE ${cJSON_SOURCE_DIR})

target_link_libraries(inkbunny_favorite_experiment PRIVATE CURL::libcurl cjson)
