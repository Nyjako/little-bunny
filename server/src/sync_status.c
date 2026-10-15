#include "sync_status.h"

#include <goblin/cstr.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct server_sync_status
{
    pthread_mutex_t mutex;
    bool active;
    char *source;
    char *search_label;
    int position;
    int total;
    time_t started_at;
};

server_sync_status_t *server_sync_status_create(void)
{
    server_sync_status_t *status = calloc(1, sizeof(server_sync_status_t));
    if (!status) {
        return NULL;
    }
    if (pthread_mutex_init(&status->mutex, NULL) != 0) {
        free(status);
        return NULL;
    }
    return status;
}

void server_sync_status_destroy(server_sync_status_t *status)
{
    if (!status) {
        return;
    }
    pthread_mutex_destroy(&status->mutex);
    free(status->source);
    free(status->search_label);
    free(status);
}

void server_sync_status_set_active(server_sync_status_t *status, const char *source, const char *search_label, int position, int total)
{
    pthread_mutex_lock(&status->mutex);
    free(status->source);
    free(status->search_label);
    status->active = true;
    status->source = goblin_copy_cstr(source);
    status->search_label = search_label ? goblin_copy_cstr(search_label) : NULL;
    status->position = position;
    status->total = total;
    status->started_at = time(NULL);
    pthread_mutex_unlock(&status->mutex);
}

void server_sync_status_clear(server_sync_status_t *status)
{
    pthread_mutex_lock(&status->mutex);
    free(status->source);
    free(status->search_label);
    status->source = NULL;
    status->search_label = NULL;
    status->active = false;
    status->position = 0;
    status->total = 0;
    pthread_mutex_unlock(&status->mutex);
}

void server_sync_status_get(server_sync_status_t *status, server_sync_status_snapshot_t *out)
{
    memset(out, 0, sizeof(*out));
    pthread_mutex_lock(&status->mutex);
    out->active = status->active;
    out->source = status->source ? goblin_copy_cstr(status->source) : NULL;
    out->search_label = status->search_label ? goblin_copy_cstr(status->search_label) : NULL;
    out->position = status->position;
    out->total = status->total;
    out->started_at = status->started_at;
    pthread_mutex_unlock(&status->mutex);
}

void server_sync_status_snapshot_free(server_sync_status_snapshot_t *snapshot)
{
    if (!snapshot) {
        return;
    }
    free(snapshot->source);
    free(snapshot->search_label);
    snapshot->source = NULL;
    snapshot->search_label = NULL;
}
