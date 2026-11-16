#include "secret_prompt.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <termios.h>
#include <unistd.h>
#endif

bool bunny_cli_stdin_is_tty(void)
{
#ifdef _WIN32
    return _isatty(_fileno(stdin)) != 0;
#else
    return isatty(STDIN_FILENO) != 0;
#endif
}

#ifndef _WIN32

void bunny_cli_prompt_secret(const char *prompt, char *out_buf, size_t out_buf_size)
{
    struct termios old_termios;
    struct termios new_termios;
    tcgetattr(STDIN_FILENO, &old_termios);
    new_termios = old_termios;
    new_termios.c_lflag &= ~(tcflag_t)ECHO;
    tcsetattr(STDIN_FILENO, TCSANOW, &new_termios);

    fprintf(stderr, "%s", prompt);
    fflush(stderr);
    if (fgets(out_buf, (int)out_buf_size, stdin)) {
        size_t len = strlen(out_buf);
        if (len > 0 && out_buf[len - 1] == '\n') {
            out_buf[len - 1] = '\0';
        }
    } else {
        out_buf[0] = '\0';
    }

    tcsetattr(STDIN_FILENO, TCSANOW, &old_termios);
    fprintf(stderr, "\n");
}

#else /* _WIN32 */

void bunny_cli_prompt_secret(const char *prompt, char *out_buf, size_t out_buf_size)
{
    HANDLE handle = GetStdHandle(STD_INPUT_HANDLE);
    DWORD old_mode = 0;
    GetConsoleMode(handle, &old_mode);
    SetConsoleMode(handle, old_mode & ~(DWORD)ENABLE_ECHO_INPUT);

    fprintf(stderr, "%s", prompt);
    fflush(stderr);
    if (fgets(out_buf, (int)out_buf_size, stdin)) {
        size_t len = strlen(out_buf);
        if (len > 0 && out_buf[len - 1] == '\n') {
            out_buf[len - 1] = '\0';
        }
    } else {
        out_buf[0] = '\0';
    }

    SetConsoleMode(handle, old_mode);
    fprintf(stderr, "\n");
}

#endif
