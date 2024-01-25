/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static const char *
program_of_csum (const char *csumtype)
{
  if (STRCASEEQ (csumtype, "crc"))
    return "cksum";
  else if (STRCASEEQ (csumtype, "md5"))
    return "md5sum";
  else if (STRCASEEQ (csumtype, "sha1"))
    return "sha1sum";
  else if (STRCASEEQ (csumtype, "sha224"))
    return "sha224sum";
  else if (STRCASEEQ (csumtype, "sha256"))
    return "sha256sum";
  else if (STRCASEEQ (csumtype, "sha384"))
    return "sha384sum";
  else if (STRCASEEQ (csumtype, "sha512"))
    return "sha512sum";
  else if (STRCASEEQ (csumtype, "gost"))
    return "gostsum";
  else if (STRCASEEQ (csumtype, "gost12"))
    return "gost12sum";
  else {
    reply_with_error ("unknown checksum type, expecting crc|md5|sha1|sha224|sha256|sha384|sha512|gost|gost12");
    return NULL;
  }
}

static char *
checksum (const char *csumtype, int fd)
{
  const char *program;
  char *out;
  CLEANUP_FREE char *err = NULL;
  int flags, r;
  size_t len;

  program = program_of_csum (csumtype);
  if (program == NULL)
    return NULL;

  pulse_mode_start ();

  flags = COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN | fd;
  r = commandf (&out, &err, flags, program, NULL);
  if (r == -1) {
    pulse_mode_cancel ();
    reply_with_error ("%s: %s", program, err);
    free (out);
    return NULL;
  }

  /* Split it at the first whitespace. */
  len = strcspn (out, " \t\n");
  out[len] = '\0';

  pulse_mode_end ();

  return out;			/* Caller frees. */
}

char *
do_checksum (const char *csumtype, const char *path)
{
  CLEANUP_CLOSE int fd = -1;

  CHROOT_IN;
  fd = open (path, O_RDONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  return checksum (csumtype, fd);
}

char *
do_checksum_device (const char *csumtype, const char *device)
{
  CLEANUP_CLOSE int fd = -1;

  fd = open (device, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("%s", device);
    return NULL;
  }

  return checksum (csumtype, fd);
}

/* Has one FileOut parameter. */
int
do_checksums_out (const char *csumtype, const char *dir)
{
  struct stat statbuf;
  int r;
  const char *program;
  CLEANUP_FREE char *str = NULL;
  CLEANUP_FREE char *sysrootdir = NULL;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  FILE *fp;

  str = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (str == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  program = program_of_csum (csumtype);
  if (program == NULL)
    return -1;

  sysrootdir = sysroot_path (dir);
  if (!sysrootdir) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = stat (sysrootdir, &statbuf);
  if (r == -1) {
    reply_with_perror ("%s", dir);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: not a directory", dir);
    return -1;
  }

  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return -1;
  }
  fprintf (fp, "cd ");
  shell_quote (sysrootdir, fp);
  fprintf (fp, " && %s -type f -print0 | %s -0 %s",
           "find", "xargs", program);
  if (fclose (fp) == EOF)
    goto cmd_error;

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    return -1;
  }

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (str, 1, GUESTFS_MAX_CHUNK_SIZE, fp)) > 0) {
    if (send_file_write (str, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fread: %s: %m\n", dir);
    send_file_end (1);                /* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %s: %m\n", dir);
    send_file_end (1);                /* Cancel. */
    return -1;
  }

  if (send_file_end (0))        /* Normal end of file. */
    return -1;

  return 0;
}
