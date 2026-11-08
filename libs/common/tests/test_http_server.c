#include "test_http_server.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "bunny_common/thread.h"

struct bunny_test_http_server
{
    int listen_fd;
    uint16_t port;
    int request_count;
    bunny_thread_t thread;
    char *response;
    size_t response_len;
};

static void *serve_loop(void *arg)
{
    bunny_test_http_server_t *server = (bunny_test_http_server_t *)arg;
    int i;
    for (i = 0; i < server->request_count; i++) {
        int conn_fd = accept(server->listen_fd, NULL, NULL);
        if (conn_fd < 0) {
            continue;
        }
        char request_buf[4096];
        /* Don't need to actually parse the request -- every test using this
         * server only cares about the response it gets back. One recv() is
         * enough for any plain GET a test here ever issues. */
        recv(conn_fd, request_buf, sizeof(request_buf), 0);
        size_t sent = 0;
        while (sent < server->response_len) {
            ssize_t n = send(conn_fd, server->response + sent, server->response_len - sent, 0);
            if (n <= 0) {
                break;
            }
            sent += (size_t)n;
        }
        close(conn_fd);
    }
    close(server->listen_fd);
    return NULL;
}

bunny_test_http_server_t *bunny_test_http_server_start(const char *status_line, const char *body, size_t body_len, int request_count)
{
    int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        return NULL;
    }

    int reuse = 1;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    addr.sin_port = 0; /* ask the OS to assign an ephemeral port */

    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(listen_fd);
        return NULL;
    }
    if (listen(listen_fd, 4) != 0) {
        close(listen_fd);
        return NULL;
    }

    struct sockaddr_in bound_addr;
    socklen_t bound_addr_len = sizeof(bound_addr);
    if (getsockname(listen_fd, (struct sockaddr *)&bound_addr, &bound_addr_len) != 0) {
        close(listen_fd);
        return NULL;
    }

    bunny_test_http_server_t *server = malloc(sizeof(*server));
    if (!server) {
        close(listen_fd);
        return NULL;
    }
    server->listen_fd = listen_fd;
    server->port = ntohs(bound_addr.sin_port);
    server->request_count = request_count;

    size_t header_cap = 128;
    char *header = malloc(header_cap);
    int header_len = snprintf(header, header_cap, "HTTP/1.1 %s\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n", status_line, body_len);

    server->response_len = (size_t)header_len + body_len;
    server->response = malloc(server->response_len);
    memcpy(server->response, header, (size_t)header_len);
    if (body_len > 0) {
        memcpy(server->response + header_len, body, body_len);
    }
    free(header);

    if (bunny_thread_create(&server->thread, serve_loop, server) != 0) {
        close(listen_fd);
        free(server->response);
        free(server);
        return NULL;
    }

    return server;
}

char *bunny_test_http_server_url(bunny_test_http_server_t *server)
{
    char *url = malloc(64);
    snprintf(url, 64, "http://127.0.0.1:%u/", (unsigned int)server->port);
    return url;
}

void bunny_test_http_server_join(bunny_test_http_server_t *server)
{
    bunny_thread_join(server->thread);
    free(server->response);
    free(server);
}
