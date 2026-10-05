add_executable(bunny_core_test_core test_core.c)
target_link_libraries(bunny_core_test_core PRIVATE bunny_core unity::framework)
add_test(NAME bunny_core_test_core COMMAND bunny_core_test_core)

add_executable(bunny_core_test_sync test_sync.c)
target_link_libraries(bunny_core_test_sync PRIVATE bunny_core unity::framework)
target_compile_definitions(bunny_core_test_sync PRIVATE FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
add_test(NAME bunny_core_test_sync COMMAND bunny_core_test_sync)

add_executable(bunny_core_test_queue test_queue.c)
target_link_libraries(bunny_core_test_queue PRIVATE bunny_core unity::framework)
target_compile_definitions(bunny_core_test_queue PRIVATE FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
add_test(NAME bunny_core_test_queue COMMAND bunny_core_test_queue)

add_executable(bunny_core_test_downloads test_downloads.c)
target_link_libraries(bunny_core_test_downloads PRIVATE bunny_core unity::framework)
target_compile_definitions(bunny_core_test_downloads PRIVATE FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
add_test(NAME bunny_core_test_downloads COMMAND bunny_core_test_downloads)
