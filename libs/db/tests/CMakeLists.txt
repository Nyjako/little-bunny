add_executable(bunny_db_test_db test_db.c)
target_link_libraries(bunny_db_test_db PRIVATE bunny_db unity::framework)
add_test(NAME bunny_db_test_db COMMAND bunny_db_test_db)
