/*
 * EXPERIMENTAL / UNOFFICIAL. This talks to inkbunny.net's own website - the
 * same requests your browser makes when you click the favorite stars - NOT
 * the documented API. libinkbunny (see libs/inkbunny) deliberately does not
 * implement favoriting because the official API has no endpoint for it (see
 * docs/architecture.md, "Inkbunny API constraints"). This tool exists only
 * to test whether the website's internal flow could work as an unofficial
 * fallback. It is fragile: it depends on exact HTML markup Inkbunny could
 * change at any time, and it is not wired into libinkbunny or the rest of
 * the app. Reverse-engineered 2026-09-28 from js82/fav.rev01.js's
 * favProcess() function via the browser's network/script inspection.
 *
 * Flow:
 *   1. GET  /login.php                 -> scrape the login form's CSRF token
 *   2. POST /login_process.php         -> username+password+token, using the
 *      cookie jar from step 1; treated as success if the final URL isn't
 *      back on /login.php
 *   3. GET  <submission page>          -> scrape that page's "global_token"
 *      (a session-bound CSRF token used by all the site's authenticated
 *      AJAX calls, not just favoriting)
 *   4. POST /submissionfav_process.php -> token, submission_id, stars,
 *      add/remove
 *
 * Your password is read from stdin without echoing, used once, then
 * overwritten in memory - never logged, printed, or stored.
 *
 * Usage: inkbunny_favorite_experiment <username> <submission_id> <add|remove> [stars=1-3]
 */

#include <curl/curl.h>
#include <cJSON.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

typedef struct {
    char *data;
    size_t len;
} buffer_t;

static size_t write_cb(char *ptr, size_t size, size_t nmemb, void *userdata) {
    buffer_t *buf = (buffer_t *)userdata;
    size_t add = size * nmemb;
    char *new_data = realloc(buf->data, buf->len + add + 1);
    if (!new_data) {
        return 0;
    }
    buf->data = new_data;
    memcpy(buf->data + buf->len, ptr, add);
    buf->len += add;
    buf->data[buf->len] = '\0';
    return add;
}

static void buffer_free(buffer_t *buf) {
    free(buf->data);
    buf->data = NULL;
    buf->len = 0;
}

/* Finds `attr="attr_value"` (e.g. name="token" or id="general-global_token"),
 * then returns a copy of the nearest value="..." within the same <input ...>
 * tag (checked in both directions, since attribute order varies between the
 * two tokens this tool needs). Returns NULL if not found. */
static char *extract_input_value(const char *html, const char *attr, const char *attr_value) {
    char needle[160];
    snprintf(needle, sizeof(needle), "%s=\"%s\"", attr, attr_value);

    const char *match = strstr(html, needle);
    if (!match) {
        return NULL;
    }

    const char *tag_start = match;
    while (tag_start > html && *tag_start != '<') {
        tag_start--;
    }
    const char *tag_end = strchr(match, '>');
    if (!tag_end) {
        return NULL;
    }

    const char *value_marker = "value=\"";
    const char *value_pos = strstr(tag_start, value_marker);
    if (!value_pos || value_pos > tag_end) {
        return NULL;
    }
    value_pos += strlen(value_marker);

    const char *end = strchr(value_pos, '"');
    if (!end) {
        return NULL;
    }

    size_t len = (size_t)(end - value_pos);
    char *result = malloc(len + 1);
    if (!result) {
        return NULL;
    }
    memcpy(result, value_pos, len);
    result[len] = '\0';
    return result;
}

static bool http_get(CURL *curl, const char *url, buffer_t *out) {
    memset(out, 0, sizeof(*out));
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, NULL);
    return curl_easy_perform(curl) == CURLE_OK;
}

static bool http_post_form(CURL *curl, const char *url, const char *body, bool want_json_header,
                            buffer_t *out) {
    memset(out, 0, sizeof(*out));
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out);

    struct curl_slist *headers = NULL;
    if (want_json_header) {
        headers = curl_slist_append(headers, "Accept: application/json");
    }
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    CURLcode res = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, NULL);
    return res == CURLE_OK;
}

static char *url_encode(CURL *curl, const char *value) {
    char *escaped = curl_easy_escape(curl, value, 0);
    if (!escaped) {
        return NULL;
    }
    char *copy = strdup(escaped);
    curl_free(escaped);
    return copy;
}

static void read_password(char *buf, size_t buf_size) {
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

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr,
                "usage: %s <username> <submission_id> <add|remove> [stars=1-3]\n"
                "  Prompts for the password on stdin (not echoed).\n"
                "  Example: %s myusername 3948160 add 1\n",
                argv[0], argv[0]);
        return 1;
    }

    const char *username = argv[1];
    const char *submission_id = argv[2];
    const char *action = argv[3];
    const char *stars = argc > 4 ? argv[4] : "1";

    bool is_add = strcmp(action, "add") == 0;
    bool is_remove = strcmp(action, "remove") == 0;
    if (!is_add && !is_remove) {
        fprintf(stderr, "action must be \"add\" or \"remove\", got \"%s\"\n", action);
        return 1;
    }
    if (is_add && strcmp(stars, "1") != 0 && strcmp(stars, "2") != 0 && strcmp(stars, "3") != 0) {
        fprintf(stderr, "stars must be 1, 2, or 3, got \"%s\"\n", stars);
        return 1;
    }

    char password[256];
    read_password(password, sizeof(password));

    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL *curl = curl_easy_init();
    if (!curl) {
        fprintf(stderr, "curl_easy_init failed\n");
        return 1;
    }

    curl_easy_setopt(curl, CURLOPT_COOKIEFILE, ""); /* enables the in-memory cookie engine */
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "LittleBunny-experiment/0.1 (unofficial-favorite-test)");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);

    int exit_code = 1;
    buffer_t page = {0};
    char *login_token = NULL;
    char *encoded_user = NULL;
    char *encoded_pass = NULL;
    char *encoded_login_token = NULL;
    char *global_token = NULL;
    char *encoded_global_token = NULL;
    char *login_body = NULL;
    char *fav_body = NULL;

    printf("[1/4] GET /login.php ...\n");
    if (!http_get(curl, "https://inkbunny.net/login.php", &page)) {
        fprintf(stderr, "failed to fetch the login page\n");
        goto cleanup;
    }
    login_token = extract_input_value(page.data, "name", "token");
    if (!login_token) {
        fprintf(stderr, "could not find the login form's CSRF token -- page markup may have changed\n");
        goto cleanup;
    }
    buffer_free(&page);

    encoded_user = url_encode(curl, username);
    encoded_pass = url_encode(curl, password);
    encoded_login_token = url_encode(curl, login_token);
    memset(password, 0, sizeof(password)); /* done with the plaintext password */
    if (!encoded_user || !encoded_pass || !encoded_login_token) {
        fprintf(stderr, "out of memory\n");
        goto cleanup;
    }

    {
        size_t needed = strlen("token=&username=&password=") + strlen(encoded_login_token) +
                         strlen(encoded_user) + strlen(encoded_pass) + 1;
        login_body = malloc(needed);
        if (!login_body) {
            fprintf(stderr, "out of memory\n");
            goto cleanup;
        }
        snprintf(login_body, needed, "token=%s&username=%s&password=%s", encoded_login_token, encoded_user,
                 encoded_pass);
    }

    printf("[2/4] POST /login_process.php ...\n");
    if (!http_post_form(curl, "https://inkbunny.net/login_process.php", login_body, false, &page)) {
        fprintf(stderr, "login request failed\n");
        goto cleanup;
    }

    {
        char *final_url = NULL;
        curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &final_url);
        if (final_url && strstr(final_url, "/login.php")) {
            fprintf(stderr, "login failed (redirected back to the login page) -- check username/password\n");
            goto cleanup;
        }
    }
    printf("      login looks successful (redirected away from /login.php)\n");
    buffer_free(&page);

    {
        char submission_url[256];
        snprintf(submission_url, sizeof(submission_url), "https://inkbunny.net/s/%s", submission_id);
        printf("[3/4] GET %s to read this session's global_token ...\n", submission_url);
        if (!http_get(curl, submission_url, &page)) {
            fprintf(stderr, "failed to fetch the submission page\n");
            goto cleanup;
        }
    }
    global_token = extract_input_value(page.data, "id", "general-global_token");
    if (!global_token) {
        fprintf(stderr, "could not find general-global_token on the submission page -- markup may have "
                        "changed, or the submission id doesn't exist\n");
        goto cleanup;
    }
    buffer_free(&page);

    encoded_global_token = url_encode(curl, global_token);
    if (!encoded_global_token) {
        fprintf(stderr, "out of memory\n");
        goto cleanup;
    }

    {
        size_t needed = strlen("token=&stars=&add=false&remove=false&submission_id=") +
                         strlen(encoded_global_token) + strlen(stars) + strlen(submission_id) + 1;
        fav_body = malloc(needed);
        if (!fav_body) {
            fprintf(stderr, "out of memory\n");
            goto cleanup;
        }
        snprintf(fav_body, needed, "token=%s&stars=%s&add=%s&remove=%s&submission_id=%s", encoded_global_token,
                 is_add ? stars : "0", is_add ? "true" : "false", is_remove ? "true" : "false", submission_id);
    }

    printf("[4/4] POST /submissionfav_process.php (%s, stars=%s) ...\n", action, is_add ? stars : "0");
    if (!http_post_form(curl, "https://inkbunny.net/submissionfav_process.php", fav_body, true, &page)) {
        fprintf(stderr, "favorite request failed\n");
        goto cleanup;
    }

    {
        /* Prototype.js wraps successful JSON responses as "/*-secure-\n{...}\n*\/"
         * (an old defense against JSON-hijacking); strip that before parsing. */
        const char *json_start = strchr(page.data, '{');
        const char *json_end = strrchr(page.data, '}');
        if (!json_start || !json_end || json_end < json_start) {
            fprintf(stderr, "unexpected response: %s\n", page.data);
            goto cleanup;
        }
        size_t json_len = (size_t)(json_end - json_start) + 1;
        char *json_only = malloc(json_len + 1);
        if (!json_only) {
            fprintf(stderr, "out of memory\n");
            goto cleanup;
        }
        memcpy(json_only, json_start, json_len);
        json_only[json_len] = '\0';

        cJSON *parsed = cJSON_Parse(json_only);
        free(json_only);
        if (!parsed) {
            fprintf(stderr, "failed to parse response JSON: %s\n", page.data);
            goto cleanup;
        }
        cJSON *success = cJSON_GetObjectItemCaseSensitive(parsed, "success");
        if (cJSON_IsString(success) && strcmp(success->valuestring, "yes") == 0) {
            printf("Success: submission %s is now %s (stars=%s)\n", submission_id,
                   is_add ? "favorited" : "un-favorited", is_add ? stars : "0");
            exit_code = 0;
        } else {
            char *dump = cJSON_Print(parsed);
            fprintf(stderr, "server did not report success: %s\n", dump ? dump : "(unknown)");
            free(dump);
        }
        cJSON_Delete(parsed);
    }

cleanup:
    buffer_free(&page);
    free(login_token);
    free(encoded_user);
    free(encoded_pass);
    free(encoded_login_token);
    free(global_token);
    free(encoded_global_token);
    free(login_body);
    free(fav_body);
    curl_easy_cleanup(curl);
    curl_global_cleanup();
    return exit_code;
}
