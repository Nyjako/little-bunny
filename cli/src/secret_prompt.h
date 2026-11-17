#ifndef BUNNY_CLI_SECRET_PROMPT_H
#define BUNNY_CLI_SECRET_PROMPT_H

#include <goblin/secret_prompt.h>

/* bunny_cli_stdin_is_tty/bunny_cli_prompt_secret are now thin forwarding
 * wrappers over GOBLIN's own goblin_stdin_is_tty/goblin_prompt_secret
 * (vendored) -- bunny_cli used to hand-roll this itself (termios/Windows
 * console-mode echo toggling), now upstreamed into GOBLIN, so this just
 * delegates. Same static-inline-forwarding pattern as bunny_common/
 * thread.h -- safe to include from any number of translation units. */

static inline bool bunny_cli_stdin_is_tty(void)
{
    return goblin_stdin_is_tty();
}

static inline void bunny_cli_prompt_secret(const char *prompt, char *out_buf, size_t out_buf_size)
{
    goblin_prompt_secret(prompt, out_buf, out_buf_size);
}

#endif /* BUNNY_CLI_SECRET_PROMPT_H */
