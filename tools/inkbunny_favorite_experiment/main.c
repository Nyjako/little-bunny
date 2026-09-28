/*
 * Thin CLI over libinkbunny's UNOFFICIAL favorite/unfavorite functions (see
 * inkbunny/unofficial_favorites.h and docs/architecture.md, "Unofficial
 * favorite flow"). This exists to exercise those functions against a real
 * account without wiring them into the app yet.
 *
 * Your password is read from stdin without echoing, used once to log in,
 * then overwritten in memory - never logged, printed, or stored.
 *
 * Usage: inkbunny_favorite_experiment <username> <submission_id> <add|remove> [stars=1-3]
 */

#include <inkbunny/client.h>
#include <inkbunny/unofficial_favorites.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static void read_password(char *buf, size_t buf_size)
{
    struct termios oldt;
    struct termios newt;
    tcgetattr(STDIN_FILENO, &oldt);
    newt = oldt;
    newt.c_lflag &= ~(tcflag_t)ECHO;
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);

    printf("Password: ");
    fflush(stdout);
    if (fgets(buf, (int)buf_size, stdin)) {
        size_t len = strlen(buf);
        if (len > 0 && buf[len - 1] == '\n') {
            buf[len - 1] = '\0';
        }
    } else {
        buf[0] = '\0';
    }

    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    printf("\n");
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr,
                "usage: %s <username> <submission_id> <add|remove> [stars=1-3]\n"
                "  Prompts for the password on stdin (not echoed).\n"
                "  Example: %s myusername 3948160 add 1\n",
                argv[0], argv[0]);
        return 1;
    }

    const char *username = argv[1];
    int64_t submission_id = strtoll(argv[2], NULL, 10);
    const char *action = argv[3];
    int stars = argc > 4 ? (int)strtol(argv[4], NULL, 10) : 1;

    bool is_add = strcmp(action, "add") == 0;
    bool is_remove = strcmp(action, "remove") == 0;
    if (!is_add && !is_remove) {
        fprintf(stderr, "action must be \"add\" or \"remove\", got \"%s\"\n", action);
        return 1;
    }

    char password[256];
    read_password(password, sizeof(password));

    inkbunny_config_t config;
    memset(&config, 0, sizeof(config));
    inkbunny_client_t *client = inkbunny_client_create(&config);
    if (!client) {
        fprintf(stderr, "inkbunny_client_create failed\n");
        return 1;
    }

    printf("Logging into the website...\n");
    inkbunny_result_t result = inkbunny_website_login(client, username, password);
    memset(password, 0, sizeof(password)); /* done with the plaintext password */
    if (result != INKBUNNY_OK) {
        fprintf(stderr, "website login failed: %s\n", inkbunny_result_to_string(result));
        inkbunny_client_destroy(client);
        return 1;
    }

    if (is_add) {
        printf("Adding favorite (stars=%d) to submission %lld...\n", stars, (long long)submission_id);
        result = inkbunny_favorite_add(client, submission_id, stars);
    } else {
        printf("Removing favorite from submission %lld...\n", (long long)submission_id);
        result = inkbunny_favorite_remove(client, submission_id);
    }

    if (result == INKBUNNY_OK) {
        printf("Success: submission %lld is now %s\n", (long long)submission_id, is_add ? "favorited" : "un-favorited");
    } else {
        fprintf(stderr, "failed: %s\n", inkbunny_result_to_string(result));
    }

    inkbunny_client_destroy(client);
    return result == INKBUNNY_OK ? 0 : 1;
}
