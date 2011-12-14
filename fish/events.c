/* guestfish - the filesystem interactive shell
 * Copyright (C) 2011 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <guestfs.h>

#include "hash.h"
#include "hash-pjw.h"

#include "fish.h"

/* The hash table maps names to multiple (linked list of) event handlers. */
static Hash_table *event_handlers;

struct entry {
  struct entry *next;           /* Next entry in linked list. */
  char *name;                   /* Event name. */
  char *command;                /* Shell script / command that runs. */
  uint64_t event_bitmask;       /* Events this is registered for. */
  int eh;        /* Event handle (from guestfs_set_event_callback). */
};

static void
entry_free (void *x)
{
  if (x) {
    struct entry *p = x;
    entry_free (p->next);
    free (p->name);
    free (p->command);
    free (p);
  }
}

static size_t
entry_hash (void const *x, size_t table_size)
{
  struct entry const *p = x;
  return hash_pjw (p->name, table_size);
}

static bool
entry_compare (void const *x, void const *y)
{
  struct entry const *p = x;
  struct entry const *q = y;
  return STREQ (p->name, q->name);
}

void
init_event_handlers (void)
{
  assert (event_handlers == NULL);
  event_handlers =
    hash_initialize (64, NULL, entry_hash, entry_compare, entry_free);
}

void
free_event_handlers (void)
{
  assert (event_handlers != NULL);
  hash_free (event_handlers);
  event_handlers = NULL;
}

static void
do_event_handler (guestfs_h *g,
                  void *opaque,
                  uint64_t event,
                  int event_handle,
                  int flags,
                  const char *buf, size_t buf_len,
                  const uint64_t *array, size_t array_len)
{
  pid_t pid;
  const char *argv[8 + array_len];
  const char *shell;
  struct entry *entry = opaque;
  size_t i, j;
  char *s;

  pid = fork ();
  if (pid == -1) {
    perror ("event handler: fork");
    return;
  }

  if (pid == 0) {               /* Child process. */
    shell = getenv ("SHELL");
    if (!shell)
      shell = "/bin/sh";

    setenv ("EVENT", event_name_of_event_bitmask (event), 1);

    /* Construct the command and arguments. */
    i = 0;
    argv[i++] = shell;
    argv[i++] = "-c";
    argv[i++] = entry->command;
    argv[i++] = ""; /* $0 */

    if (buf != NULL)
      /* XXX: So far, buf is always ASCII NUL-terminated.  There is no
       * way to pass arbitrary 8 bit buffers.
       */
      argv[i++] = buf;

    for (j = 0; j < array_len; ++j) {
      if (asprintf (&s, "%" PRIu64, array[j]) == -1) {
        perror ("event handler: asprintf");
        _exit (EXIT_FAILURE);
      }
      argv[i++] = s;
    }

    argv[i++] = NULL;

    execvp (argv[0], (void *) argv);
    perror (argv[0]);

    _exit (EXIT_FAILURE);
  }

  if (waitpid (pid, NULL, 0) == -1)
    perror ("event handler: waitpid");
}

int
run_event (const char *cmd, size_t argc, char *argv[])
{
  int r;
  struct entry *entry = NULL, *old_entry;

  if (argc != 3) {
    fprintf (stderr,
             _("use 'event <name> <eventset> <script>' to register an event handler\n"));
    goto error;
  }

  entry = calloc (1, sizeof *entry);
  if (entry == NULL) {
    perror ("calloc");
    goto error;
  }
  entry->eh = -1;

  r = event_bitmask_of_event_set (argv[1], &entry->event_bitmask);
  if (r == -1)
    goto error;

  entry->name = strdup (argv[0]);
  if (entry->name == NULL) {
    perror ("strdup");
    goto error;
  }
  entry->command = strdup (argv[2]);
  if (entry->command == NULL) {
    perror ("strdup");
    goto error;
  }

  entry->eh =
    guestfs_set_event_callback (g, do_event_handler,
                                entry->event_bitmask, 0, entry);
  if (entry->eh == -1)
    goto error;

  r = hash_insert_if_absent (event_handlers, entry, (const void **) &old_entry);
  if (r == -1)
    goto error;
  if (r == 0) {                 /* old_entry set to existing entry */
    entry->next = old_entry->next;
    /* XXX are we allowed to update the old entry? */
    old_entry->next = entry;
  }

  return 0;

 error:
  if (entry) {
    if (entry->eh >= 0)
      guestfs_delete_event_callback (g, entry->eh);
    free (entry->name);
    free (entry->command);
    free (entry);
  }
  return -1;
}

int
run_delete_event (const char *cmd, size_t argc, char *argv[])
{
  if (argc != 1) {
    fprintf (stderr,
             _("use 'delete-event <name>' to delete an event handler\n"));
    return -1;
  }

  const struct entry key = { .name = bad_cast (argv[0]) };
  struct entry *entry, *p;

  entry = hash_delete (event_handlers, &key);
  if (!entry) {
    fprintf (stderr, _("delete-event: %s: no such event handler\n"), argv[0]);
    return -1;
  }

  /* Delete them from the handle. */
  p = entry;
  while (p) {
    guestfs_delete_event_callback (g, p->eh);
    p = p->next;
  }

  /* Free the structures. */
  entry_free (entry);

  return 0;
}

static bool
list_event (void *x, void *data)
{
  struct entry *entry = x;

  while (entry) {
    printf ("\"%s\" (%d): ", entry->name, entry->eh);
    print_event_set (entry->event_bitmask, stdout);
    printf (": %s\n", entry->command);
    entry = entry->next;
  }

  return 1;
}

int
run_list_events (const char *cmd, size_t argc, char *argv[])
{
  if (argc != 0) {
    fprintf (stderr,
             _("use 'list-events' to list event handlers\n"));
    return -1;
  }

  hash_do_for_each (event_handlers, list_event, NULL);
  return 0;
}
