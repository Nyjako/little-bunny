/* Test-only stand-in for the real Flutter app's --cli-handshake entry point
 * (see app/lib/main.dart's _runCliHandshake / app/lib/cli_handshake.dart).
 * Speaks the exact same stdin/stdout protocol so cli/tests/test_handshake.c
 * can exercise bunny_cli_handshake_run's real spawn/pipe code without ever
 * building or running Flutter. Behavior is controlled entirely through
 * environment variables -- the real protocol only ever passes
 * "--cli-handshake" as an argument, so this reuses the same channel a real
 * fork()/CreateProcess() child already inherits, rather than inventing a
 * second, test-only argument convention:
 *
 *   BUNNY_CLI_TEST_SECRET    unset/empty = app-lock is off, any input (or
 *                            none) succeeds. Set = the exact secret that
 *                            must be supplied, or this responds "locked".
 *   BUNNY_CLI_TEST_MODE      "none" | "standalone" (default) | "networked"
 *   BUNNY_CLI_TEST_BEHAVIOR  "normal" (default) | "crash" (exits before
 *                            reading/writing anything) | "slow" (sleeps
 *                            briefly before responding normally) |
 *                            "garbage" (writes invalid JSON) | "no_newline"
 *                            (writes valid JSON with no trailing newline) |
 *                            "noisy_stdout" (writes a few lines of
 *                            non-JSON text to stdout before the real
 *                            response -- reproduces a real Flutter build's
 *                            own native plugins printing banner/diagnostic
 *                            text to stdout ahead of the app's own
 *                            response, confirmed live with media_kit/fvp)
 *   BUNNY_CLI_TEST_NO_DOWNLOAD_FOLDER  if set to anything, standalone/
 *                            networked responses report
 *                            "downloadDestinationFolder":null instead of a
 *                            real path -- the rare case the app's own
 *                            OS-Downloads-directory fallback failed too.
 *   BUNNY_CLI_TEST_NO_QUEUE_DB  if set to anything, a networked response
 *                            omits downloadQueueDbPath/downloadQueueUserAgent
 *                            entirely -- an app build from before those
 *                            fields existed.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

static void sleep_briefly(void)
{
#ifdef _WIN32
    Sleep(200);
#else
    usleep(200 * 1000);
#endif
}

int main(void)
{
    const char *behavior = getenv("BUNNY_CLI_TEST_BEHAVIOR");
    if (behavior && strcmp(behavior, "crash") == 0) {
        return 1;
    }
    if (behavior && strcmp(behavior, "slow") == 0) {
        sleep_briefly();
    }

    char line[256];
    if (!fgets(line, sizeof(line), stdin)) {
        line[0] = '\0';
    }
    size_t len = strlen(line);
    if (len > 0 && line[len - 1] == '\n') {
        line[len - 1] = '\0';
    }

    if (behavior && strcmp(behavior, "garbage") == 0) {
        printf("not json at all\n");
        return 0;
    }

    if (behavior && strcmp(behavior, "noisy_stdout") == 0) {
        printf("some native plugin's banner\n");
        printf("0.40.1 (git deadbeef) - some other plugin's own version line\n");
    }

    const char *expected_secret = getenv("BUNNY_CLI_TEST_SECRET");
    if (expected_secret && expected_secret[0] != '\0' && strcmp(expected_secret, line) != 0) {
        printf("{\"ok\":false,\"error\":\"locked\"}\n");
        return 1;
    }

    const char *mode = getenv("BUNNY_CLI_TEST_MODE");
    if (!mode) {
        mode = "standalone";
    }

    const char *download_folder_json = getenv("BUNNY_CLI_TEST_NO_DOWNLOAD_FOLDER") ? "null" : "\"/fake/downloads\"";

    char response[512];
    if (strcmp(mode, "none") == 0) {
        strcpy(response, "{\"ok\":true,\"mode\":\"none\"}");
    } else if (strcmp(mode, "networked") == 0) {
        const char *queue_db_fields = getenv("BUNNY_CLI_TEST_NO_QUEUE_DB") ? "" : "\"downloadQueueDbPath\":\"/fake/downloads.db\",\"downloadQueueUserAgent\":\"LittleBunny/1.0.0\",";
        snprintf(response, sizeof(response), "{\"ok\":true,\"mode\":\"networked\",\"serverBaseUrl\":\"https://bunny.example:9443\",\"bearerToken\":\"test-token\",\"certFingerprint\":\"abc123\",%s\"downloadDestinationFolder\":%s}", queue_db_fields, download_folder_json);
    } else {
        snprintf(response, sizeof(response), "{\"ok\":true,\"mode\":\"standalone\",\"dbPath\":\"/fake/bunny.db\",\"userAgent\":\"LittleBunny/1.0.0\",\"downloadDestinationFolder\":%s}", download_folder_json);
    }

    if (behavior && strcmp(behavior, "no_newline") == 0) {
        printf("%s", response);
    } else {
        printf("%s\n", response);
    }
    return 0;
}
