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

add_executable(bunny_cli_test_destination test_destination.c)
target_link_libraries(bunny_cli_test_destination PRIVATE bunny_cli_lib unity::framework)
add_test(NAME bunny_cli_test_destination COMMAND bunny_cli_test_destination)

# Exercises rest_client.c's request-building/response-mapping/url-encoding
# logic against an injected fake transport, plus the fingerprint-comparison
# math the real pinned transport's OpenSSL verify callback uses -- the
# actual TLS handshake/pinning is manual-only (see test_rest_client.c's own
# doc comment), same precedent as http_bunny_repository_test.dart's own
# fake-transport-only automated coverage.
add_executable(bunny_cli_test_rest_client test_rest_client.c)
target_link_libraries(bunny_cli_test_rest_client PRIVATE bunny_cli_lib unity::framework)
add_test(NAME bunny_cli_test_rest_client COMMAND bunny_cli_test_rest_client)

# Exercises commands.c's own claim/process loop against a real bunny_core_t
# and a real local HTTP server (bunny_test_http_server, the same fixture
# bunny_core_test_download already uses) -- POSIX sockets only, same
# Linux-only restriction that fixture's own header already documents.
add_executable(bunny_cli_test_download_workers test_download_workers.c)
target_link_libraries(bunny_cli_test_download_workers PRIVATE bunny_cli_lib bunny_test_http_server unity::framework)
add_test(NAME bunny_cli_test_download_workers COMMAND bunny_cli_test_download_workers)

# bunny_cli_parse_download_spec's own id-extraction/validation logic, in
# isolation -- the real pool:/search: resolution (a live search, a saved-
# search lookup) needs a real core/rest client and is covered by manual
# end-to-end verification instead (see the PR description).
add_executable(bunny_cli_test_download_specs test_download_specs.c)
target_link_libraries(bunny_cli_test_download_specs PRIVATE bunny_cli_lib unity::framework)
add_test(NAME bunny_cli_test_download_specs COMMAND bunny_cli_test_download_specs)
