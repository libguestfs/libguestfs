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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/resource.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

/* This command exposes debugging information, internals and
 * status.  There is no comprehensive documentation for this
 * command.  You have to look at the source code in this file
 * to find out what you can do.
 *
 * Commands always output a freeform string.
 *
 * Since libguestfs 1.5.7, the debug command has been enabled
 * by default for all builds (previously you had to enable it
 * in configure).  This command is not part of the stable ABI
 * and may change at any time.
 */

struct cmd {
  const char *cmd;
  char * (*f) (const char *subcmd, int argc, char *const *const argv);
};

static char *debug_help (const char *subcmd, int argc, char *const *const argv);
static char *debug_binaries (const char *subcmd, int argc, char *const *const argv);
static char *debug_core_pattern (const char *subcmd, int argc, char *const *const argv);
static char *debug_env (const char *subcmd, int argc, char *const *const argv);
static char *debug_fds (const char *subcmd, int argc, char *const *const argv);
static char *debug_ldd (const char *subcmd, int argc, char *const *const argv);
static char *debug_ls (const char *subcmd, int argc, char *const *const argv);
static char *debug_ll (const char *subcmd, int argc, char *const *const argv);
static char *debug_progress (const char *subcmd, int argc, char *const *const argv);
static char *debug_qtrace (const char *subcmd, int argc, char *const *const argv);
static char *debug_segv (const char *subcmd, int argc, char *const *const argv);
static char *debug_sh (const char *subcmd, int argc, char *const *const argv);

static struct cmd cmds[] = {
  { "help", debug_help },
  { "binaries", debug_binaries },
  { "core_pattern", debug_core_pattern },
  { "env", debug_env },
  { "fds", debug_fds },
  { "ldd", debug_ldd },
  { "ls", debug_ls },
  { "ll", debug_ll },
  { "progress", debug_progress },
  { "qtrace", debug_qtrace },
  { "segv", debug_segv },
  { "sh", debug_sh },
  { NULL, NULL }
};

char *
do_debug (const char *subcmd, char *const *argv)
{
  int argc, i;

  for (i = argc = 0; argv[i] != NULL; ++i)
    argc++;

  for (i = 0; cmds[i].cmd != NULL; ++i) {
    if (STRCASEEQ (subcmd, cmds[i].cmd))
      return cmds[i].f (subcmd, argc, argv);
  }

  reply_with_error ("use 'debug help 0' to list the supported commands");
  return NULL;
}

static char *
debug_help (const char *subcmd, int argc, char *const *const argv)
{
  int len, i;
  char *r, *p;

  r = strdup ("Commands supported:");
  if (!r) {
    reply_with_perror ("strdup");
    return NULL;
  }

  len = strlen (r);
  for (i = 0; cmds[i].cmd != NULL; ++i) {
    len += strlen (cmds[i].cmd) + 1; /* space + new command */
    p = realloc (r, len + 1);	     /* +1 for the final NUL */
    if (p == NULL) {
      reply_with_perror ("realloc");
      free (r);
      return NULL;
    }
    r = p;

    strcat (r, " ");
    strcat (r, cmds[i].cmd);
  }

  return r;
}

/* Show open FDs. */
static char *
debug_fds (const char *subcmd, int argc, char *const *const argv)
{
  int r;
  char *out;
  size_t size;
  FILE *fp;
  DIR *dir;
  struct dirent *d;
  char fname[256], link[256];
  struct stat statbuf;

  fp = open_memstream (&out, &size);
  if (!fp) {
    reply_with_perror ("open_memstream");
    return NULL;
  }

  dir = opendir ("/proc/self/fd");
  if (!dir) {
    reply_with_perror ("opendir: /proc/self/fd");
    fclose (fp);
    return NULL;
  }

  while ((d = readdir (dir)) != NULL) {
    if (STREQ (d->d_name, ".") || STREQ (d->d_name, ".."))
      continue;

    snprintf (fname, sizeof fname, "/proc/self/fd/%s", d->d_name);

    r = lstat (fname, &statbuf);
    if (r == -1) {
      reply_with_perror ("stat: %s", fname);
      fclose (fp);
      free (out);
      closedir (dir);
      return NULL;
    }

    if (S_ISLNK (statbuf.st_mode)) {
      r = readlink (fname, link, sizeof link - 1);
      if (r == -1) {
        reply_with_perror ("readline: %s", fname);
        fclose (fp);
        free (out);
        closedir (dir);
        return NULL;
      }
      link[r] = '\0';

      fprintf (fp, "%2s %s\n", d->d_name, link);
    } else
      fprintf (fp, "%2s 0%o\n", d->d_name, statbuf.st_mode);
  }

  fclose (fp);

  if (closedir (dir) == -1) {
    reply_with_perror ("closedir");
    free (out);
    return NULL;
  }

  return out;
}

/* Force a segfault in the daemon. */
static char *
debug_segv (const char *subcmd, int argc, char *const *const argv)
{
  /* http://blog.llvm.org/2011/05/what-every-c-programmer-should-know.html
   * "Dereferencing a NULL Pointer: contrary to popular belief,
   * dereferencing a null pointer in C is undefined. It is not defined
   * to trap [...]"
   */
  volatile int *ptr = NULL;
  *ptr = 1;
  return NULL;
}

/* Run an arbitrary shell command using /bin/sh from the appliance.
 *
 * Note this is somewhat different from the ordinary guestfs_sh command
 * because it's not using the guest shell, and is not chrooted.
 */
static char *
debug_sh (const char *subcmd, int argc, char *const *const argv)
{
  if (argc < 1) {
    reply_with_error ("sh: expecting a command to run");
    return NULL;
  }

  char *cmd;
  int len, i, j;

  /* guestfish splits the parameter(s) into a list of strings,
   * and we have to reassemble them here.  Not ideal. XXX
   */
  for (i = len = 0; i < argc; ++i)
    len += strlen (argv[i]) + 1;
  cmd = malloc (len);
  if (!cmd) {
    reply_with_perror ("malloc");
    return NULL;
  }
  for (i = j = 0; i < argc; ++i) {
    len = strlen (argv[i]);
    memcpy (&cmd[j], argv[i], len);
    j += len;
    cmd[j] = ' ';
    j++;
  }
  cmd[j-1] = '\0';

  /* Set up some environment variables. */
  setenv ("root", sysroot, 1);
  if (access ("/sys/block/sda", F_OK) == 0)
    setenv ("sd", "sd", 1);
  else if (access ("/sys/block/hda", F_OK) == 0)
    setenv ("sd", "hd", 1);
  else if (access ("/sys/block/vda", F_OK) == 0)
    setenv ("sd", "vd", 1);

  char *err;
  int r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                    "/bin/sh", "-c", cmd, NULL);
  free (cmd);

  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return NULL;
  }

  return err;
}

/* Print the environment that commands get (by running external printenv). */
static char *
debug_env (const char *subcmd, int argc, char *const *const argv)
{
  int r;
  char *out, *err;

  r = command (&out, &err, "printenv", NULL);
  if (r == -1) {
    reply_with_error ("printenv: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return out;
}

/* Return binaries in the appliance.
 * See tests/regressions/rhbz727178.sh
 */
static char *
debug_binaries (const char *subcmd, int argc, char *const *const argv)
{
  int r;
  char *out, *err;

  const char cmd[] =
    "find / -xdev -type f -executable "
    "| xargs file -i "
    "| grep application/x-executable "
    "| gawk -F: '{print $1}'";

  r = command (&out, &err, "sh", "-c", cmd, NULL);
  if (r == -1) {
    reply_with_error ("find: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return out;
}

/* Run 'ldd' on a file from the appliance.
 * See tests/regressions/rhbz727178.sh
 */
static char *
debug_ldd (const char *subcmd, int argc, char *const *const argv)
{
  int r;
  char *out, *err, *ret;

  if (argc != 1) {
    reply_with_error ("ldd: no file argument");
    return NULL;
  }

  /* Note that 'ldd' doesn't fail if it finds errors.  We have to grep
   * for errors in the regression test instead.  'ldd' only fails here
   * if the binary is not a binary at all (eg. for shell scripts).
   * Also 'ldd' randomly sends messages to stderr and errors to stdout
   * depending on the phase of the moon.
   */
  r = command (&out, &err, "ldd", "-r", argv[0], NULL);
  if (r == -1) {
    reply_with_error ("ldd: %s: %s", argv[0], err);
    free (out);
    free (err);
    return NULL;
  }

  /* Concatenate stdout and stderr in the result. */
  ret = realloc (out, strlen (out) + strlen (err) + 1);
  if (ret == NULL) {
    reply_with_perror ("realloc");
    free (out);
    free (err);
    return NULL;
  }

  strcat (ret, err);
  free (err);

  return ret;
}

/* List files in the appliance. */
static char *
debug_ls (const char *subcmd, int argc, char *const *const argv)
{
  int len = count_strings (argv);
  const char *cargv[len+3];
  int i;

  cargv[0] = "ls";
  cargv[1] = "-a";
  for (i = 0; i < len; ++i)
    cargv[2+i] = argv[i];
  cargv[2+len] = NULL;

  int r;
  char *out, *err;

  r = commandv (&out, &err, (void *) cargv);
  if (r == -1) {
    reply_with_error ("ls: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return out;
}

/* List files in the appliance. */
static char *
debug_ll (const char *subcmd, int argc, char *const *const argv)
{
  int len = count_strings (argv);
  const char *cargv[len+3];
  int i;

  cargv[0] = "ls";
  cargv[1] = "-la";
  for (i = 0; i < len; ++i)
    cargv[2+i] = argv[i];
  cargv[2+len] = NULL;

  int r;
  char *out, *err;

  r = commandv (&out, &err, (void *) cargv);
  if (r == -1) {
    reply_with_error ("ll: %s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return out;
}

/* Generate progress notification messages in order to test progress bars. */
static char *
debug_progress (const char *subcmd, int argc, char *const *const argv)
{
  if (argc < 1) {
  error:
    reply_with_error ("progress: expecting arg (time in seconds as string)");
    return NULL;
  }

  char *secs_str = argv[0];
  unsigned secs;
  if (sscanf (secs_str, "%u", &secs) != 1 || secs == 0)
    goto error;

  unsigned i;
  unsigned tsecs = secs * 10;   /* 1/10ths of seconds */
  for (i = 1; i <= tsecs; ++i) {
    usleep (100000);
    notify_progress ((uint64_t) i, (uint64_t) tsecs);
  }

  char *ret = strdup ("ok");
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}

/* Enable core dumping to the given core pattern.
 * Note that this pattern is relative to any chroot of the process which
 * crashes. This means that if you want to write the core file to the guest's
 * storage the pattern must start with /sysroot only if the command which
 * crashes doesn't chroot.
 */
static char *
debug_core_pattern (const char *subcmd, int argc, char *const *const argv)
{
  if (argc < 1) {
    reply_with_error ("core_pattern: expecting a core pattern");
    return NULL;
  }

  const char *pattern = argv[0];
  const size_t pattern_len = strlen(pattern);

#define CORE_PATTERN "/proc/sys/kernel/core_pattern"
  int fd = open (CORE_PATTERN, O_WRONLY);
  if (fd == -1) {
    reply_with_perror ("open: " CORE_PATTERN);
    return NULL;
  }
  if (write (fd, pattern, pattern_len) < (ssize_t) pattern_len) {
    reply_with_perror ("write: " CORE_PATTERN);
    return NULL;
  }
  if (close (fd) == -1) {
    reply_with_perror ("close: " CORE_PATTERN);
    return NULL;
  }

  struct rlimit limit = {
    .rlim_cur = RLIM_INFINITY,
    .rlim_max = RLIM_INFINITY
  };
  if (setrlimit (RLIMIT_CORE, &limit) == -1) {
    reply_with_perror ("setrlimit (RLIMIT_CORE)");
    return NULL;
  }

  char *ret = strdup ("ok");
  if (NULL == ret) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}

static int
write_cb (void *fd_ptr, const void *buf, size_t len)
{
  int fd = *(int *)fd_ptr;
  return xwrite (fd, buf, len);
}

/* This requires a non-upstream qemu patch.  See contrib/visualize-alignment/
 * directory in the libguestfs source tree.
 */
static char *
debug_qtrace (const char *subcmd, int argc, char *const *const argv)
{
  int enable;

  if (argc != 2) {
  bad_args:
    reply_with_error ("qtrace <device> <on|off>");
    return NULL;
  }

  if (STREQ (argv[1], "on"))
    enable = 1;
  else if (STREQ (argv[1], "off"))
    enable = 0;
  else
    goto bad_args;

  /* This does a sync and flushes all caches. */
  if (do_drop_caches (3) == -1)
    return NULL;

  /* Note this doesn't do device name translation or check this is a device. */
  int fd = open (argv[0], O_RDONLY | O_DIRECT);
  if (fd == -1) {
    reply_with_perror ("qtrace: %s: open", argv[0]);
    return NULL;
  }

  /* The pattern of reads is what signals to the analysis program that
   * tracing should be started or stopped.  Note this assumes both 512
   * byte sectors, and that O_DIRECT will let us do 512 byte aligned
   * reads.  We ought to read the sector size of the device and use
   * that instead (XXX).  The analysis program currently assumes 512
   * byte sectors anyway.
   */
#define QTRACE_SIZE 512
  const int patterns[2][5] = {
    { 2, 15, 21, 2, -1 }, /* disable trace */
    { 2, 21, 15, 2, -1 }  /* enable trace */
  };
  void *buf;
  size_t i;

  /* For O_DIRECT, buffer must be aligned too (thanks Matt).
   * Note posix_memalign has this strange errno behaviour.
   */
  errno = posix_memalign (&buf, QTRACE_SIZE, QTRACE_SIZE);
  if (errno != 0) {
    reply_with_perror ("posix_memalign");
    close (fd);
    return NULL;
  }

  for (i = 0; patterns[enable][i] >= 0; ++i) {
    if (lseek (fd, patterns[enable][i]*QTRACE_SIZE, SEEK_SET) == -1) {
      reply_with_perror ("qtrace: %s: lseek", argv[0]);
      close (fd);
      free (buf);
      return NULL;
    }

    if (read (fd, buf, QTRACE_SIZE) == -1) {
      reply_with_perror ("qtrace: %s: read", argv[0]);
      close (fd);
      free (buf);
      return NULL;
    }
  }

  close (fd);
  free (buf);

  /* This does a sync and flushes all caches. */
  if (do_drop_caches (3) == -1)
    return NULL;

  char *ret = strdup ("ok");
  if (NULL == ret) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}

/* Has one FileIn parameter. */
int
do_debug_upload (const char *filename, int mode)
{
  /* Not chrooted - this command lets you upload a file to anywhere
   * in the appliance.
   */
  int fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, mode);

  if (fd == -1) {
    int err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("%s", filename);
    return -1;
  }

  int r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    int err = errno;
    cancel_receive ();
    errno = err;
    reply_with_error ("write error: %s", filename);
    close (fd);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    /* This error is ignored by the library since it initiated the
     * cancel.  Nevertheless we must send an error reply here.
     */
    reply_with_error ("file upload cancelled");
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", filename);
    return -1;
  }

  return 0;
}
