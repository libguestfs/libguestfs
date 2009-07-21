/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

int
do_touch (char *path)
{
  int fd;
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_CREAT | O_NOCTTY, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

#ifdef HAVE_FUTIMENS
  r = futimens (fd, NULL);
#else
  r = futimes (fd, NULL);
#endif
  if (r == -1) {
    reply_with_perror ("futimens: %s", path);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

char *
do_cat (char *path)
{
  int fd;
  int alloc, size, r, max;
  char *buf, *buf2;

  NEED_ROOT (NULL);
  ABS_PATH (path,NULL);

  CHROOT_IN;
  fd = open (path, O_RDONLY);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return NULL;
  }

  /* Read up to GUESTFS_MESSAGE_MAX - <overhead> bytes.  If it's
   * larger than that, we need to return an error instead (for
   * correctness).
   */
  max = GUESTFS_MESSAGE_MAX - 1000;
  buf = NULL;
  size = alloc = 0;

  for (;;) {
    if (size >= alloc) {
      alloc += 8192;
      if (alloc > max) {
	reply_with_error ("cat: %s: file is too large for message buffer",
			  path);
	free (buf);
	close (fd);
	return NULL;
      }
      buf2 = realloc (buf, alloc);
      if (buf2 == NULL) {
	reply_with_perror ("realloc");
	free (buf);
	close (fd);
	return NULL;
      }
      buf = buf2;
    }

    r = read (fd, buf + size, alloc - size);
    if (r == -1) {
      reply_with_perror ("read: %s", path);
      free (buf);
      close (fd);
      return NULL;
    }
    if (r == 0) {
      buf[size] = '\0';
      break;
    }
    if (r > 0)
      size += r;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    free (buf);
    return NULL;
  }

  return buf;			/* caller will free */
}

char **
do_read_lines (char *path)
{
  char **r = NULL;
  int size = 0, alloc = 0;
  FILE *fp;
  char *line = NULL;
  size_t len = 0;
  ssize_t n;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  CHROOT_IN;
  fp = fopen (path, "r");
  CHROOT_OUT;

  if (!fp) {
    reply_with_perror ("fopen: %s", path);
    return NULL;
  }

  while ((n = getline (&line, &len, fp)) != -1) {
    /* Remove either LF or CRLF. */
    if (n >= 2 && line[n-2] == '\r' && line[n-1] == '\n')
      line[n-2] = '\0';
    else if (n >= 1 && line[n-1] == '\n')
      line[n-1] = '\0';

    if (add_string (&r, &size, &alloc, line) == -1) {
      free (line);
      fclose (fp);
      return NULL;
    }
  }

  free (line);

  if (add_string (&r, &size, &alloc, NULL) == -1) {
    fclose (fp);
    return NULL;
  }

  if (fclose (fp) == EOF) {
    reply_with_perror ("fclose: %s", path);
    free_strings (r);
    return NULL;
  }

  return r;
}

int
do_rm (char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = unlink (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("unlink: %s", path);
    return -1;
  }

  return 0;
}

int
do_chmod (int mode, char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = chmod (path, mode);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("chmod: %s: 0%o", path, mode);
    return -1;
  }

  return 0;
}

int
do_chown (int owner, int group, char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = chown (path, owner, group);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("chown: %s: %d.%d", path, owner, group);
    return -1;
  }

  return 0;
}

int
do_exists (char *path)
{
  int r;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = access (path, F_OK);
  CHROOT_OUT;

  return r == 0;
}

int
do_is_file (char *path)
{
  int r;
  struct stat buf;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  CHROOT_IN;
  r = lstat (path, &buf);
  CHROOT_OUT;

  if (r == -1) {
    if (errno != ENOENT && errno != ENOTDIR) {
      reply_with_perror ("stat: %s", path);
      return -1;
    }
    else
      return 0;			/* Not a file. */
  }

  return S_ISREG (buf.st_mode);
}

int
do_write_file (char *path, char *content, int size)
{
  int fd;

  NEED_ROOT (-1);
  ABS_PATH (path, -1);

  if (size == 0)
    size = strlen (content);

  CHROOT_IN;
  fd = open (path, O_WRONLY | O_TRUNC | O_CREAT | O_NOCTTY, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  if (xwrite (fd, content, size) == -1) {
    reply_with_perror ("write");
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

char *
do_read_file (char *path, size_t *size_r)
{
  int fd;
  struct stat statbuf;
  char *r;

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  CHROOT_IN;
  fd = open (path, O_RDONLY);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return NULL;
  }

  if (fstat (fd, &statbuf) == -1) {
    reply_with_perror ("fstat: %s", path);
    close (fd);
    return NULL;
  }

  *size_r = statbuf.st_size;
  /* The actual limit on messages is smaller than this.  This
   * check just limits the amount of memory we'll try and allocate
   * here.  If the message is larger than the real limit, that will
   * be caught later when we try to serialize the message.
   */
  if (*size_r >= GUESTFS_MESSAGE_MAX) {
    reply_with_error ("read_file: %s: file is too large for the protocol, use gusetfs_download instead", path);
    close (fd);
    return NULL;
  }
  r = malloc (*size_r);
  if (r == NULL) {
    reply_with_perror ("malloc");
    close (fd);
    return NULL;
  }

  if (xread (fd, r, *size_r) == -1) {
    reply_with_perror ("read: %s", path);
    close (fd);
    free (r);
    return NULL;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    free (r);
    return NULL;
  }

  return r;
}

/* This runs the 'file' command. */
char *
do_file (char *path)
{
  char *out, *err;
  int r, freeit = 0;
  char *buf;
  int len;

  NEED_ROOT_OR_IS_DEVICE (path, NULL);
  ABS_PATH (path, NULL);

  if (strncmp (path, "/dev/", 5) == 0)
    buf = (char *) path;
  else {
    buf = sysroot_path (path);
    if (!buf) {
      reply_with_perror ("malloc");
      return NULL;
    }
    freeit = 1;
  }

  /* file(1) manpage claims "file returns 0 on success, and non-zero on
   * error", but this is evidently not true.  It always returns 0, in
   * every scenario I can think up.  So check the target is readable
   * first.
   */
  if (access (buf, R_OK) == -1) {
    if (freeit) free (buf);
    reply_with_perror ("access: %s", path);
    return NULL;
  }

  r = command (&out, &err, "file", "-bsL", buf, NULL);
  if (freeit) free (buf);

  if (r == -1) {
    free (out);
    reply_with_error ("file: %s: %s", path, err);
    free (err);
    return NULL;
  }
  free (err);

  /* We need to remove the trailing \n from output of file(1). */
  len = strlen (out);
  if (out[len-1] == '\n')
    out[len-1] = '\0';

  return out;			/* caller frees */
}

/* zcat | file */
char *
do_zfile (char *method, char *path)
{
  int len;
  char *cmd;
  FILE *fp;
  char line[256];

  NEED_ROOT (NULL);
  ABS_PATH (path, NULL);

  len = 2 * strlen (path) + sysroot_len + 64;
  cmd = malloc (len);
  if (!cmd) {
    reply_with_perror ("malloc");
    return NULL;
  }

  if (strcmp (method, "gzip") == 0 || strcmp (method, "compress") == 0)
    strcpy (cmd, "zcat");
  else if (strcmp (method, "bzip2") == 0)
    strcpy (cmd, "bzcat");
  else {
    free (cmd);
    reply_with_error ("zfile: unknown method");
    return NULL;
  }

  strcat (cmd, " ");
  strcat (cmd, sysroot);
  shell_quote (cmd + strlen (cmd), len - strlen (cmd), path);
  strcat (cmd, " | file -bsL -");

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    free (cmd);
    return NULL;
  }

  free (cmd);

  if (fgets (line, sizeof line, fp) == NULL) {
    reply_with_perror ("zfile: fgets");
    fclose (fp);
    return NULL;
  }

  if (fclose (fp) == -1) {
    reply_with_perror ("zfile: fclose");
    return NULL;
  }

  len = strlen (line);
  if (len > 0 && line[len-1] == '\n')
    line[len-1] = '\0';

  return strdup (line);
}
