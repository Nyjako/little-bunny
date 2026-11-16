#include "handshake.h"

#include <cJSON.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

/* The app's stdout is not guaranteed to contain *only* the one handshake
 * response line: a real Flutter build can link native plugins (confirmed
 * live -- this app's own media_kit/fvp registration prints a version banner
 * straight to stdout) that write their own text there before -- or
 * interleaved with -- the app's own response, entirely outside this
 * protocol's or buildCliHandshakeResponse's control. So rather than trust
 * "the first line is the real one," this reads everything the child writes
 * until it exits and closes the pipe (bounded below), then scans every line
 * for the one that actually parses as a valid response, ignoring the rest. */
#define BUNNY_CLI_HANDSHAKE_MAX_TOTAL_OUTPUT (256 * 1024)

static char *dup_string(const char *s)
{
    if (!s) {
        return NULL;
    }
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy) {
        memcpy(copy, s, len);
    }
    return copy;
}

void bunny_cli_handshake_payload_free(bunny_cli_handshake_payload_t *payload)
{
    if (!payload) {
        return;
    }
    free(payload->db_path);
    free(payload->user_agent);
    free(payload->server_base_url);
    free(payload->bearer_token);
    free(payload->cert_fingerprint);
    memset(payload, 0, sizeof(*payload));
}

const char *bunny_cli_handshake_result_to_string(bunny_cli_handshake_result_t result)
{
    switch (result) {
        case BUNNY_CLI_HANDSHAKE_OK:
            return "ok";
        case BUNNY_CLI_HANDSHAKE_LOCKED:
            return "the app is locked";
        case BUNNY_CLI_HANDSHAKE_APP_NOT_FOUND:
            return "the app executable was not found next to bunny_cli";
        case BUNNY_CLI_HANDSHAKE_SPAWN_FAILED:
            return "failed to launch the app";
        case BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR:
            return "the app did not respond with a valid handshake reply";
    }
    return "unknown handshake error";
}

/* Parses one handshake response line into *out -- see handshake.h's own doc
 * comment on bunny_cli_handshake_payload_t for the field/mode shapes, and
 * the top-level plan for the exact JSON contract this mirrors
 * (buildCliHandshakeResponse on the Dart side is the producer). */
static bunny_cli_handshake_result_t parse_response_line(const char *line, bunny_cli_handshake_payload_t *out)
{
    cJSON *json = cJSON_Parse(line);
    if (!json) {
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    cJSON *ok = cJSON_GetObjectItemCaseSensitive(json, "ok");
    if (!cJSON_IsBool(ok)) {
        cJSON_Delete(json);
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    if (!cJSON_IsTrue(ok)) {
        cJSON *error = cJSON_GetObjectItemCaseSensitive(json, "error");
        bunny_cli_handshake_result_t result = (cJSON_IsString(error) && strcmp(error->valuestring, "locked") == 0) ? BUNNY_CLI_HANDSHAKE_LOCKED : BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
        cJSON_Delete(json);
        return result;
    }

    cJSON *mode = cJSON_GetObjectItemCaseSensitive(json, "mode");
    if (!cJSON_IsString(mode)) {
        cJSON_Delete(json);
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    memset(out, 0, sizeof(*out));
    bunny_cli_handshake_result_t result = BUNNY_CLI_HANDSHAKE_OK;
    if (strcmp(mode->valuestring, "none") == 0) {
        out->mode = BUNNY_CLI_MODE_NONE;
    } else if (strcmp(mode->valuestring, "standalone") == 0) {
        cJSON *db_path = cJSON_GetObjectItemCaseSensitive(json, "dbPath");
        cJSON *user_agent = cJSON_GetObjectItemCaseSensitive(json, "userAgent");
        if (!cJSON_IsString(db_path) || !cJSON_IsString(user_agent)) {
            result = BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
        } else {
            out->mode = BUNNY_CLI_MODE_STANDALONE;
            out->db_path = dup_string(db_path->valuestring);
            out->user_agent = dup_string(user_agent->valuestring);
        }
    } else if (strcmp(mode->valuestring, "networked") == 0) {
        cJSON *server_base_url = cJSON_GetObjectItemCaseSensitive(json, "serverBaseUrl");
        cJSON *bearer_token = cJSON_GetObjectItemCaseSensitive(json, "bearerToken");
        cJSON *cert_fingerprint = cJSON_GetObjectItemCaseSensitive(json, "certFingerprint");
        if (!cJSON_IsString(server_base_url) || !cJSON_IsString(bearer_token) || !cJSON_IsString(cert_fingerprint)) {
            result = BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
        } else {
            out->mode = BUNNY_CLI_MODE_NETWORKED;
            out->server_base_url = dup_string(server_base_url->valuestring);
            out->bearer_token = dup_string(bearer_token->valuestring);
            out->cert_fingerprint = dup_string(cert_fingerprint->valuestring);
        }
    } else {
        result = BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    cJSON_Delete(json);
    if (result != BUNNY_CLI_HANDSHAKE_OK) {
        bunny_cli_handshake_payload_free(out);
    }
    return result;
}

/* Scans `output` (everything captured from the child's stdout, see
 * BUNNY_CLI_HANDSHAKE_MAX_TOTAL_OUTPUT's own comment on why this can't just
 * trust the first line) line by line, returning the first one that parses
 * as a valid response -- BUNNY_CLI_HANDSHAKE_OK or BUNNY_CLI_HANDSHAKE_LOCKED
 * both count as "the app validly answered"; anything else (a native
 * plugin's own banner text, a stray warning, ...) is silently skipped. Only
 * reports BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR once every line has been tried
 * and none of them validated. */
static bunny_cli_handshake_result_t find_and_parse_response(const char *output, bunny_cli_handshake_payload_t *out)
{
    if (!output) {
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    const char *line_start = output;
    while (*line_start) {
        const char *newline = strchr(line_start, '\n');
        size_t line_len = newline ? (size_t)(newline - line_start) : strlen(line_start);

        char *line = malloc(line_len + 1);
        if (!line) {
            return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
        }
        memcpy(line, line_start, line_len);
        line[line_len] = '\0';

        bunny_cli_handshake_result_t result = parse_response_line(line, out);
        free(line);
        if (result == BUNNY_CLI_HANDSHAKE_OK || result == BUNNY_CLI_HANDSHAKE_LOCKED) {
            return result;
        }

        if (!newline) {
            break;
        }
        line_start = newline + 1;
    }

    return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
}

#ifndef _WIN32

char *bunny_cli_find_app_executable(void)
{
    char self_path[4096];
    ssize_t len = readlink("/proc/self/exe", self_path, sizeof(self_path) - 1);
    if (len <= 0) {
        return NULL;
    }
    self_path[len] = '\0';

    char *last_slash = strrchr(self_path, '/');
    if (!last_slash) {
        return NULL;
    }
    *last_slash = '\0';

    static const char *app_name = "/little_bunny";
    char *result = malloc(strlen(self_path) + strlen(app_name) + 1);
    if (!result) {
        return NULL;
    }
    strcpy(result, self_path);
    strcat(result, app_name);
    return result;
}

static bool app_executable_exists(const char *app_exe_path)
{
    return access(app_exe_path, X_OK) == 0;
}

/* Reads everything the child writes to its stdout until EOF (it closes the
 * write end once it exits, right after the "--cli-handshake" branch writes
 * its one response line -- see handshake.h's own protocol doc comment),
 * into a freshly allocated, NUL-terminated buffer, growing it as needed up
 * to BUNNY_CLI_HANDSHAKE_MAX_TOTAL_OUTPUT. Never returns NULL on its own
 * (an empty read just yields an empty string) -- the caller's
 * find_and_parse_response is what decides whether anything useful was in
 * there. */
static char *read_all_output(int read_fd)
{
    size_t capacity = 4096;
    size_t total = 0;
    char *buf = malloc(capacity);
    if (!buf) {
        return NULL;
    }
    while (total + 1 < BUNNY_CLI_HANDSHAKE_MAX_TOTAL_OUTPUT) {
        if (total + 1 >= capacity) {
            size_t new_capacity = capacity * 2;
            char *grown = realloc(buf, new_capacity);
            if (!grown) {
                break;
            }
            buf = grown;
            capacity = new_capacity;
        }
        ssize_t n = read(read_fd, buf + total, capacity - total - 1);
        if (n <= 0) {
            break;
        }
        total += (size_t)n;
    }
    buf[total] = '\0';
    return buf;
}

static bunny_cli_handshake_result_t spawn_and_capture_output(const char *app_exe_path, const char *supplied_secret, char **out_output)
{
    int stdin_pipe[2];
    int stdout_pipe[2];
    if (pipe(stdin_pipe) != 0) {
        return BUNNY_CLI_HANDSHAKE_SPAWN_FAILED;
    }
    if (pipe(stdout_pipe) != 0) {
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        return BUNNY_CLI_HANDSHAKE_SPAWN_FAILED;
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        return BUNNY_CLI_HANDSHAKE_SPAWN_FAILED;
    }

    if (pid == 0) {
        /* Child: wire the pipes up as stdin/stdout, inherit stderr as-is. */
        dup2(stdin_pipe[0], STDIN_FILENO);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        char *argv[] = {(char *)app_exe_path, (char *)"--cli-handshake", NULL};
        execv(app_exe_path, argv);
        _exit(127); /* execv only returns on failure */
    }

    /* Parent: close the ends that belong to the child. */
    close(stdin_pipe[0]);
    close(stdout_pipe[1]);

    const char *secret = supplied_secret ? supplied_secret : "";
    size_t secret_len = strlen(secret);
    bool write_ok = true;
    if (secret_len > 0) {
        write_ok = write(stdin_pipe[1], secret, secret_len) == (ssize_t)secret_len;
    }
    if (write_ok) {
        write_ok = write(stdin_pipe[1], "\n", 1) == 1;
    }
    /* Closing this (not just the written bytes) is what lets the child's
     * own line-read return instead of blocking on more input it'll never
     * get -- see handshake.h's own protocol doc comment. */
    close(stdin_pipe[1]);

    char *output = read_all_output(stdout_pipe[0]);
    close(stdout_pipe[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    if (!write_ok || !output) {
        free(output);
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    *out_output = output;
    return BUNNY_CLI_HANDSHAKE_OK;
}

#else /* _WIN32 */

char *bunny_cli_find_app_executable(void)
{
    char self_path[MAX_PATH];
    DWORD len = GetModuleFileNameA(NULL, self_path, sizeof(self_path));
    if (len == 0 || len >= sizeof(self_path)) {
        return NULL;
    }

    char *last_slash = strrchr(self_path, '\\');
    if (!last_slash) {
        return NULL;
    }
    *last_slash = '\0';

    static const char *app_name = "\\little_bunny.exe";
    char *result = malloc(strlen(self_path) + strlen(app_name) + 1);
    if (!result) {
        return NULL;
    }
    strcpy(result, self_path);
    strcat(result, app_name);
    return result;
}

static bool app_executable_exists(const char *app_exe_path)
{
    DWORD attrs = GetFileAttributesA(app_exe_path);
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

/* See the POSIX branch's read_all_output for why this reads everything
 * rather than trusting a single "first line." */
static char *read_all_output(HANDLE read_handle)
{
    size_t capacity = 4096;
    size_t total = 0;
    char *buf = malloc(capacity);
    if (!buf) {
        return NULL;
    }
    while (total + 1 < BUNNY_CLI_HANDSHAKE_MAX_TOTAL_OUTPUT) {
        if (total + 1 >= capacity) {
            size_t new_capacity = capacity * 2;
            char *grown = realloc(buf, new_capacity);
            if (!grown) {
                break;
            }
            buf = grown;
            capacity = new_capacity;
        }
        DWORD read_bytes = 0;
        BOOL ok = ReadFile(read_handle, buf + total, (DWORD)(capacity - total - 1), &read_bytes, NULL);
        if (!ok || read_bytes == 0) {
            break;
        }
        total += read_bytes;
    }
    buf[total] = '\0';
    return buf;
}

static bunny_cli_handshake_result_t spawn_and_capture_output(const char *app_exe_path, const char *supplied_secret, char **out_output)
{
    SECURITY_ATTRIBUTES sa;
    memset(&sa, 0, sizeof(sa));
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE stdin_read = NULL, stdin_write = NULL;
    HANDLE stdout_read = NULL, stdout_write = NULL;
    if (!CreatePipe(&stdin_read, &stdin_write, &sa, 0) || !CreatePipe(&stdout_read, &stdout_write, &sa, 0)) {
        return BUNNY_CLI_HANDSHAKE_SPAWN_FAILED;
    }
    /* This process's own ends must not be inherited by the child, or it
     * would hold its own write end of stdin open and this process's read
     * of stdout would never see EOF. */
    SetHandleInformation(stdin_write, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOA si;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = stdin_read;
    si.hStdOutput = stdout_write;
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof(pi));

    char cmdline[MAX_PATH + 32];
    snprintf(cmdline, sizeof(cmdline), "\"%s\" --cli-handshake", app_exe_path);

    BOOL created = CreateProcessA(app_exe_path, cmdline, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    CloseHandle(stdin_read);
    CloseHandle(stdout_write);
    if (!created) {
        CloseHandle(stdin_write);
        CloseHandle(stdout_read);
        return BUNNY_CLI_HANDSHAKE_SPAWN_FAILED;
    }
    CloseHandle(pi.hThread);

    const char *secret = supplied_secret ? supplied_secret : "";
    DWORD secret_len = (DWORD)strlen(secret);
    DWORD written = 0;
    bool write_ok = secret_len == 0 || (WriteFile(stdin_write, secret, secret_len, &written, NULL) && written == secret_len);
    if (write_ok) {
        write_ok = WriteFile(stdin_write, "\n", 1, &written, NULL) && written == 1;
    }
    CloseHandle(stdin_write); /* see the POSIX branch's own comment on why this matters */

    char *output = read_all_output(stdout_read);
    CloseHandle(stdout_read);

    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);

    if (!write_ok || !output) {
        free(output);
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }

    *out_output = output;
    return BUNNY_CLI_HANDSHAKE_OK;
}

#endif

bunny_cli_handshake_result_t bunny_cli_handshake_run(const char *app_exe_path, const char *supplied_secret, bunny_cli_handshake_payload_t *out)
{
    if (!app_exe_path || !out) {
        return BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR;
    }
    memset(out, 0, sizeof(*out));

    if (!app_executable_exists(app_exe_path)) {
        return BUNNY_CLI_HANDSHAKE_APP_NOT_FOUND;
    }

    char *output = NULL;
    bunny_cli_handshake_result_t spawn_result = spawn_and_capture_output(app_exe_path, supplied_secret, &output);
    if (spawn_result != BUNNY_CLI_HANDSHAKE_OK) {
        return spawn_result;
    }

    bunny_cli_handshake_result_t parse_result = find_and_parse_response(output, out);
    free(output);
    return parse_result;
}
