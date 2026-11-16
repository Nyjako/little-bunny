#ifndef BUNNY_CLI_SECRET_PROMPT_H
#define BUNNY_CLI_SECRET_PROMPT_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* True when this process's own stdin is an interactive terminal -- the only
 * situation where prompting for a secret makes sense (a script piping
 * input, or a non-interactive CI run, gets a clear error instead). */
bool bunny_cli_stdin_is_tty(void);

/* Prints `prompt` to stderr, reads one line from stdin with echo disabled
 * (same purpose as e.g. `sudo`'s own password prompt), and writes it,
 * NUL-terminated and with any trailing newline stripped, into `out_buf`
 * (truncated to `out_buf_size` - 1 if longer). Restores the terminal's
 * normal echo setting before returning, even on a read error. Only
 * meaningful when bunny_cli_stdin_is_tty() is true -- callers check that
 * first. */
void bunny_cli_prompt_secret(const char *prompt, char *out_buf, size_t out_buf_size);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_SECRET_PROMPT_H */
