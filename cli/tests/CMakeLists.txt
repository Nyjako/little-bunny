# Speaks the exact same stdin/stdout protocol as the real app's
# --cli-handshake entry point (app/lib/main.dart) -- lets
# bunny_cli_test_handshake exercise the real spawn/pipe code in handshake.c
# without ever building/running Flutter. Controlled via environment
# variables, see its own doc comment.
add_executable(fake_app_handshake fixtures/fake_app_handshake.c)

add_executable(bunny_cli_test_handshake test_handshake.c)
target_link_libraries(bunny_cli_test_handshake PRIVATE bunny_cli_lib unity::framework)
target_compile_definitions(bunny_cli_test_handshake PRIVATE "FAKE_APP_HANDSHAKE_PATH=\"$<TARGET_FILE:fake_app_handshake>\"")
add_test(NAME bunny_cli_test_handshake COMMAND bunny_cli_test_handshake)
