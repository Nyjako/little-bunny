add_executable(bunny_db_test_db test_db.c)
target_link_libraries(bunny_db_test_db PRIVATE bunny_db unity::framework)
if(ANDROID)
  # Bionic libc has pthread built in -- nothing to link.
elseif(NOT WIN32)
  target_link_libraries(bunny_db_test_db PRIVATE pthread)
endif()
add_test(NAME bunny_db_test_db COMMAND bunny_db_test_db)
