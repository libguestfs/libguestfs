/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <fcntl.h>

#ifdef HAVE_SYS_INOTIFY_H
#include <sys/inotify.h>
#endif

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#ifdef HAVE_SYS_INOTIFY_H
/* Currently open inotify handle, or -1 if not opened. */
static int inotify_fd = -1;

static char inotify_buf[64*1024*1024];	/* Event buffer, [0..posn-1] is valid */
static size_t inotify_posn = 0;

/* Clean up the inotify handle on daemon exit. */
static void inotify_finalize (void) __attribute__((destructor));
static void
inotify_finalize (void)
{
  if (inotify_fd >= 0) {
    close (inotify_fd);
    inotify_fd = -1;
  }
}

int
optgroup_inotify_available (void)
{
  return 1;
}
#else /* !HAVE_SYS_INOTIFY_H */
int
optgroup_inotify_available (void)
{
  return 0;
}
#endif

/* Because inotify_init does NEED_ROOT, NEED_INOTIFY implies NEED_ROOT. */
#define NEED_INOTIFY(errcode)						\
  do {									\
    if (inotify_fd == -1) {						\
      reply_with_error ("%s: you must call 'inotify_init' first to initialize inotify", __func__); \
      return (errcode);							\
    }									\
  } while (0)

#define MQE_PATH "/proc/sys/fs/inotify/max_queued_events"

int
do_inotify_init (int max_events)
{
#ifdef HAVE_SYS_INOTIFY_H
  FILE *fp;

  NEED_ROOT (, return -1);

  if (max_events < 0) {
    reply_with_error ("max_events < 0");
    return -1;
  }

  if (max_events > 0) {
    fp = fopen (MQE_PATH, "w");
    if (fp == NULL) {
      reply_with_perror (MQE_PATH);
      return -1;
    }
    fprintf (fp, "%d\n", max_events);
    fclose (fp);
  }

  if (inotify_fd >= 0)
    if (do_inotify_close () == -1)
      return -1;

#ifdef HAVE_INOTIFY_INIT1
  inotify_fd = inotify_init1 (IN_NONBLOCK | IN_CLOEXEC);
  if (inotify_fd == -1) {
    reply_with_perror ("inotify_init1");
    return -1;
  }
#else
  inotify_fd = inotify_init ();
  if (inotify_fd == -1) {
    reply_with_perror ("inotify_init");
    return -1;
  }
  if (fcntl (inotify_fd, F_SETFL, O_NONBLOCK) == -1) {
    reply_with_perror ("fcntl: O_NONBLOCK");
    close (inotify_fd);
    inotify_fd = -1;
    return -1;
  }
  if (fcntl (inotify_fd, F_SETFD, FD_CLOEXEC) == -1) {
    reply_with_perror ("fcntl: FD_CLOEXEC");
    close (inotify_fd);
    inotify_fd = -1;
    return -1;
  }
#endif

  return 0;
#else
  NOT_AVAILABLE (-1);
#endif
}

int
do_inotify_close (void)
{
#ifdef HAVE_SYS_INOTIFY_H
  NEED_INOTIFY (-1);

  if (inotify_fd == -1) {
    reply_with_error ("handle is not open");
    return -1;
  }

  if (close (inotify_fd) == -1) {
    reply_with_perror ("close");
    return -1;
  }

  inotify_fd = -1;
  inotify_posn = 0;

  return 0;
#else
  NOT_AVAILABLE (-1);
#endif
}

int64_t
do_inotify_add_watch (const char *path, int mask)
{
#ifdef HAVE_SYS_INOTIFY_H
  int64_t r;
  char *buf;

  NEED_INOTIFY (-1);

  buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = inotify_add_watch (inotify_fd, buf, mask);
  free (buf);
  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return r;
#else
  NOT_AVAILABLE (-1);
#endif
}

int
do_inotify_rm_watch (int wd)
{
#ifdef HAVE_SYS_INOTIFY_H
  NEED_INOTIFY (-1);

  if (inotify_rm_watch (inotify_fd, wd) == -1) {
    reply_with_perror ("%d", wd);
    return -1;
  }

  return 0;
#else
  NOT_AVAILABLE (-1);
#endif
}

guestfs_int_inotify_event_list *
do_inotify_read (void)
{
#ifdef HAVE_SYS_INOTIFY_H
  int space;
  guestfs_int_inotify_event_list *ret;

  NEED_INOTIFY (NULL);

  ret = malloc (sizeof *ret);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }
  ret->guestfs_int_inotify_event_list_len = 0;
  ret->guestfs_int_inotify_event_list_val = NULL;

  /* Read events that are available, but make sure we won't exceed
   * maximum message size.  In order to achieve this we have to
   * guesstimate the remaining space available.
   */
  space = GUESTFS_MESSAGE_MAX / 2;

  while (space > 0) {
    struct inotify_event *event;
    int r;
    size_t n;

    r = read (inotify_fd, inotify_buf + inotify_posn,
              sizeof (inotify_buf) - inotify_posn);
    if (r == -1) {
      if (errno == EWOULDBLOCK || errno == EAGAIN) /* End of list. */
        break;
      reply_with_perror ("read");
      goto error;
    }
    if (r == 0) {		/* End of file - we're not expecting it. */
      reply_with_error ("unexpected end of file");
      goto error;
    }

    inotify_posn += r;

    /* Read complete events from the buffer and add them to the result. */
    n = 0;
    while (n < inotify_posn) {
      guestfs_int_inotify_event *np;
      guestfs_int_inotify_event *in;

      event = (struct inotify_event *) &inotify_buf[n];

      /* Have we got a complete event in the buffer? */
#ifdef __GNUC__
      if (n + sizeof (struct inotify_event) > inotify_posn ||
          n + sizeof (struct inotify_event) + event->len > inotify_posn)
        break;
#else
#error "this code needs fixing so it works on non-GCC compilers"
#endif

      np = realloc (ret->guestfs_int_inotify_event_list_val,
                    (ret->guestfs_int_inotify_event_list_len + 1) *
                    sizeof (guestfs_int_inotify_event));
      if (np == NULL) {
        reply_with_perror ("realloc");
        goto error;
      }
      ret->guestfs_int_inotify_event_list_val = np;
      in = &ret->guestfs_int_inotify_event_list_val[ret->guestfs_int_inotify_event_list_len];
      ret->guestfs_int_inotify_event_list_len++;

      in->in_wd = event->wd;
      in->in_mask = event->mask;
      in->in_cookie = event->cookie;

      if (event->len > 0)
        in->in_name = strdup (event->name);
      else
        in->in_name = strdup (""); /* Should have optional string fields XXX. */
      if (in->in_name == NULL) {
        reply_with_perror ("strdup");
        goto error;
      }

      /* Estimate space used by this event in the message. */
      space -= 16 + 4 + strlen (in->in_name) + 4;

      /* Move pointer to next event. */
#ifdef __GNUC__
      n += sizeof (struct inotify_event) + event->len;
#else
#error "this code needs fixing so it works on non-GCC compilers"
#endif
    }

    /* 'n' now points to the first unprocessed/incomplete
     * message in the buffer. Copy that to offset 0 in the buffer.
     */
    memmove (inotify_buf, &inotify_buf[n], inotify_posn - n);
    inotify_posn -= n;
  }

  /* Return the messages. */
  return ret;

 error:
  xdr_free ((xdrproc_t) xdr_guestfs_int_inotify_event_list, (char *) ret);
  free (ret);
  return NULL;
#else
  NOT_AVAILABLE (NULL);
#endif
}

char **
do_inotify_files (void)
{
#ifdef HAVE_SYS_INOTIFY_H
  char **ret = NULL;
  int size = 0, alloc = 0;
  unsigned int i;
  FILE *fp = NULL;
  guestfs_int_inotify_event_list *events;
  char buf[PATH_MAX];
  char tempfile[] = "/tmp/inotifyXXXXXX";
  int fd;
  char cmd[64];

  NEED_INOTIFY (NULL);

  fd = mkstemp (tempfile);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return NULL;
  }

  snprintf (cmd, sizeof cmd, "sort -u > %s", tempfile);

  fp = popen (cmd, "w");
  if (fp == NULL) {
    reply_with_perror ("sort");
    return NULL;
  }

  while (1) {
    events = do_inotify_read ();
    if (events == NULL)
      goto error;

    if (events->guestfs_int_inotify_event_list_len == 0) {
      free (events);
      break;			/* End of list of events. */
    }

    for (i = 0; i < events->guestfs_int_inotify_event_list_len; ++i) {
      const char *name = events->guestfs_int_inotify_event_list_val[i].in_name;

      if (name[0] != '\0')
        fprintf (fp, "%s\n", name);
    }

    xdr_free ((xdrproc_t) xdr_guestfs_int_inotify_event_list, (char *) events);
    free (events);
  }

  pclose (fp);

  fp = fdopen (fd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", tempfile);
    unlink (tempfile);
    close (fd);
    return NULL;
  }

  while (fgets (buf, sizeof buf, fp) != NULL) {
    int len = strlen (buf);

    if (len > 0 && buf[len-1] == '\n')
      buf[len-1] = '\0';

    if (add_string (&ret, &size, &alloc, buf) == -1)
      goto error;
  }

  fclose (fp); /* implicitly closes fd */
  fp = NULL;

  if (add_string (&ret, &size, &alloc, NULL) == -1)
    goto error;

  unlink (tempfile);
  return ret;

 error:
  if (fp != NULL)
    fclose (fp);

  unlink (tempfile);
  return NULL;
#else
  NOT_AVAILABLE (NULL);
#endif
}
