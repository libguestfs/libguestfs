/* miniexpect
 * Copyright (C) 2014 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <termios.h>
#include <time.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>

#include <pcre.h>

/* RHEL 6 pcre did not define PCRE_PARTIAL_SOFT.  However PCRE_PARTIAL
 * is a synonym so use that.
 */
#ifndef PCRE_PARTIAL_SOFT
#define PCRE_PARTIAL_SOFT PCRE_PARTIAL
#endif

#include "miniexpect.h"

#define DEBUG 0

static mexp_h *
create_handle (void)
{
  mexp_h *h = malloc (sizeof *h);
  if (h == NULL)
    return NULL;

  /* Initialize the fields to default values. */
  h->fd = -1;
  h->pid = 0;
  h->timeout = 60000;
  h->read_size = 1024;
  h->pcre_error = 0;
  h->buffer = NULL;
  h->len = h->alloc = 0;
  h->next_match = -1;
  h->user1 = h->user2 = h->user3 = NULL;

  return h;
}

static void
clear_buffer (mexp_h *h)
{
  free (h->buffer);
  h->buffer = NULL;
  h->alloc = h->len = 0;
  h->next_match = -1;
}

int
mexp_close (mexp_h *h)
{
  int status = 0;

  free (h->buffer);

  if (h->fd >= 0)
    close (h->fd);
  if (h->pid > 0) {
    if (waitpid (h->pid, &status, 0) == -1)
      return -1;
  }

  free (h);

  return status;
}

mexp_h *
mexp_spawnl (const char *file, const char *arg, ...)
{
  char **argv, **new_argv;
  size_t i;
  va_list args;
  mexp_h *h;

  argv = malloc (sizeof (char *));
  if (argv == NULL)
    return NULL;
  argv[0] = (char *) arg;

  va_start (args, arg);
  for (i = 1; arg != NULL; ++i) {
    arg = va_arg (args, const char *);
    new_argv = realloc (argv, sizeof (char *) * (i+1));
    if (new_argv == NULL) {
      free (argv);
      va_end (args);
      return NULL;
    }
    argv = new_argv;
    argv[i] = (char *) arg;
  }

  h = mexp_spawnv (file, argv);
  free (argv);
  va_end (args);
  return h;
}

mexp_h *
mexp_spawnv (const char *file, char **argv)
{
  mexp_h *h = NULL;
  int fd = -1;
  int err;
  char slave[1024];
  pid_t pid = 0;

  fd = posix_openpt (O_RDWR|O_NOCTTY);
  if (fd == -1)
    goto error;

  if (grantpt (fd) == -1)
    goto error;

  if (unlockpt (fd) == -1)
    goto error;

  /* Get the slave pty name now, but don't open it in the parent. */
  if (ptsname_r (fd, slave, sizeof slave) != 0)
    goto error;

  /* Create the handle last before we fork. */
  h = create_handle ();
  if (h == NULL)
    goto error;

  pid = fork ();
  if (pid == -1)
    goto error;

  if (pid == 0) {               /* Child. */
    struct termios terminal_settings;
    int slave_fd;

    setsid ();

    /* Open the slave side of the pty.  We must do this in the child
     * after setsid so it becomes our controlling tty.
     */
    slave_fd = open (slave, O_RDWR);
    if (slave_fd == -1)
      goto error;

    /* Set raw mode. */
    tcgetattr (slave_fd, &terminal_settings);
    cfmakeraw (&terminal_settings);
    tcsetattr (slave_fd, TCSANOW, &terminal_settings);

    /* Set up stdin, stdout, stderr to point to the pty. */
    dup2 (slave_fd, 0);
    dup2 (slave_fd, 1);
    dup2 (slave_fd, 2);
    close (slave_fd);

    /* Close the master side of the pty - do this late to avoid a
     * kernel bug, see sshpass source code.
     */
    close (fd);

    /* Run the subprocess. */
    execvp (file, argv);
    perror (file);
    _exit (EXIT_FAILURE);
  }

  /* Parent. */

  h->fd = fd;
  h->pid = pid;
  return h;

 error:
  err = errno;
  if (fd >= 0)
    close (fd);
  if (pid > 0)
    waitpid (pid, NULL, 0);
  if (h != NULL)
    mexp_close (h);
  errno = err;
  return NULL;
}

enum mexp_status
mexp_expect (mexp_h *h, const mexp_regexp *regexps, int *ovector, int ovecsize)
{
  time_t start_t, now_t;
  int timeout;
  struct pollfd pfds[1];
  int r;
  ssize_t rs;

  time (&start_t);

  if (h->next_match == -1) {
    /* Fully clear the buffer, then read. */
    clear_buffer (h);
  } else {
    /* See the comment in the manual about h->next_match.  We have
     * some data remaining in the buffer, so begin by matching that.
     */
    memmove (&h->buffer[0], &h->buffer[h->next_match], h->len - h->next_match);
    h->len -= h->next_match;
    h->buffer[h->len] = '\0';
    h->next_match = -1;
    goto try_match;
  }

  for (;;) {
    /* If we've got a timeout then work out how many seconds are left.
     * Timeout == 0 is not particularly well-defined, but it probably
     * means "return immediately if there's no data to be read".
     */
    if (h->timeout >= 0) {
      time (&now_t);
      timeout = h->timeout - ((now_t - start_t) * 1000);
      if (timeout < 0)
        timeout = 0;
    }
    else
      timeout = 0;

    pfds[0].fd = h->fd;
    pfds[0].events = POLLIN;
    pfds[0].revents = 0;
    r = poll (pfds, 1, timeout);
#if DEBUG
    fprintf (stderr, "DEBUG: poll returned %d\n", r);
#endif
    if (r == -1)
      return MEXP_ERROR;

    if (r == 0)
      return MEXP_TIMEOUT;

    /* Otherwise we expect there is something to read from the file
     * descriptor.
     */
    if (h->alloc - h->len <= h->read_size) {
      char *new_buffer;
      /* +1 here allows us to store \0 after the data read */
      new_buffer = realloc (h->buffer, h->alloc + h->read_size + 1);
      if (new_buffer == NULL)
        return MEXP_ERROR;
      h->buffer = new_buffer;
      h->alloc += h->read_size;
    }
    rs = read (h->fd, h->buffer + h->len, h->read_size);
#if DEBUG
    fprintf (stderr, "DEBUG: read returned %zd\n", rs);
#endif
    if (rs == -1) {
      /* Annoyingly on Linux (I'm fairly sure this is a bug) if the
       * writer closes the connection, the entire pty is destroyed,
       * and read returns -1 / EIO.  Handle that special case here.
       */
      if (errno == EIO)
        return MEXP_EOF;
      return MEXP_ERROR;
    }
    if (rs == 0)
      return MEXP_EOF;

    /* We read something. */
    h->len += rs;
    h->buffer[h->len] = '\0';
#if DEBUG
    fprintf (stderr, "DEBUG: read %zd bytes from pty\n", rs);
    fprintf (stderr, "DEBUG: buffer content: %s\n", h->buffer);
#endif

  try_match:
    /* See if there is a full or partial match against any regexp. */
    if (regexps) {
      size_t i;
      int can_clear_buffer = 1;

      assert (h->buffer != NULL);

      for (i = 0; regexps[i].r > 0; ++i) {
        int options = regexps[i].options | PCRE_PARTIAL_SOFT;

        r = pcre_exec (regexps[i].re, regexps[i].extra,
                       h->buffer, (int)h->len, 0,
                       options,
                       ovector, ovecsize);
        h->pcre_error = r;

        if (r >= 0) {
          /* A full match. */
          if (ovector != NULL && ovecsize >= 1 && ovector[1] >= 0)
            h->next_match = ovector[1];
          else
            h->next_match = -1;
          return regexps[i].r;
        }

        else if (r == PCRE_ERROR_NOMATCH) {
          /* No match at all. */
          /* (nothing here) */
        }

        else if (r == PCRE_ERROR_PARTIAL) {
          /* Partial match.  Keep the buffer and keep reading. */
          can_clear_buffer = 0;
        }

        else {
          /* An actual PCRE error. */
          return MEXP_PCRE_ERROR;
        }
      }

      /* If none of the regular expressions matched (not partially)
       * then we can clear the buffer.  This is an optimization.
       */
      if (can_clear_buffer)
        clear_buffer (h);

    } /* if (regexps) */
  }
}

int
mexp_printf (mexp_h *h, const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;
  size_t n;
  ssize_t r;
  char *p;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0)
    return -1;

#if DEBUG
  fprintf (stderr, "DEBUG: writing: %s\n", msg);
#endif

  n = len;
  p = msg;
  while (n > 0) {
    r = write (h->fd, p, n);
    if (r == -1) {
      free (msg);
      return -1;
    }
    n -= r;
    p += r;
  }

  free (msg);
  return len;
}
