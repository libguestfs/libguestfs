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
#include <inttypes.h>
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
  char * (*f) (const char *subcmd, size_t argc, char *const *const argv);
};

static char *debug_help (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_binaries (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_core_pattern (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_device_speed (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_env (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_error (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_fds (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_ldd (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_ls (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_ll (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_print (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_progress (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_qtrace (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_segv (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_setenv (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_sh (const char *subcmd, size_t argc, char *const *const argv);
static char *debug_spew (const char *subcmd, size_t argc, char *const *const argv);
static void deliberately_cause_a_segfault (void);

static struct cmd cmds[] = {
  { "help", debug_help },
  { "binaries", debug_binaries },
  { "bmap", debug_bmap },
  { "bmap_device", debug_bmap_device },
  { "bmap_file", debug_bmap_file },
  { "core_pattern", debug_core_pattern },
  { "device_speed", debug_device_speed },
  { "env", debug_env },
  { "error", debug_error },
  { "fds", debug_fds },
  { "ldd", debug_ldd },
  { "ls", debug_ls },
  { "ll", debug_ll },
  { "print", debug_print },
  { "progress", debug_progress },
  { "qtrace", debug_qtrace },
  { "segv", debug_segv },
  { "setenv", debug_setenv },
  { "sh", debug_sh },
  { "spew", debug_spew },
  { NULL, NULL }
};

char *
do_debug (const char *subcmd, char *const *argv)
{
  size_t argc, i;

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
debug_help (const char *subcmd, size_t argc, char *const *const argv)
{
  size_t len, i;
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
debug_fds (const char *subcmd, size_t argc, char *const *const argv)
{
  int r;
  char *out;
  size_t size;
  FILE *fp;
  DIR *dir;
  struct dirent *d;
  char link[256];
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
    CLEANUP_FREE char *fname = NULL;

    if (STREQ (d->d_name, ".") || STREQ (d->d_name, ".."))
      continue;

    if (asprintf (&fname, "/proc/self/fd/%s", d->d_name) == -1) {
      reply_with_perror ("asprintf");
      fclose (fp);
      free (out);
      closedir (dir);
      return NULL;
    }

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
debug_segv (const char *subcmd, size_t argc, char *const *const argv)
{
  deliberately_cause_a_segfault ();
  return NULL;
}

/* Run an arbitrary shell command using /bin/sh from the appliance.
 *
 * Note this is somewhat different from the ordinary guestfs_sh command
 * because it's not using the guest shell, and is not chrooted.
 */
static char *
debug_sh (const char *subcmd, size_t argc, char *const *const argv)
{
  CLEANUP_FREE char *cmd = NULL;
  size_t len, i, j;

  if (argc < 1) {
    reply_with_error ("sh: expecting a command to run");
    return NULL;
  }

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
  else if (access ("/sys/block/ubda", F_OK) == 0)
    setenv ("sd", "ubd", 1);
  else if (access ("/sys/block/vda", F_OK) == 0)
    setenv ("sd", "vd", 1);

  char *err;
  int r = commandf (NULL, &err, COMMAND_FLAG_FOLD_STDOUT_ON_STDERR,
                    "/bin/sh", "-c", cmd, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return NULL;
  }

  return err;
}

/* Print the environment that commands get (by running external printenv). */
static char *
debug_env (const char *subcmd, size_t argc, char *const *const argv)
{
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;

  r = command (&out, &err, "printenv", NULL);
  if (r == -1) {
    reply_with_error ("printenv: %s", err);
    free (out);
    return NULL;
  }

  return out;
}

/* Set an environment variable in the daemon and future subprocesses. */
static char *
debug_setenv (const char *subcmd, size_t argc, char *const *const argv)
{
  char *ret;

  if (argc != 2) {
    reply_with_error ("setenv: two arguments expected");
    return NULL;
  }

  setenv (argv[0], argv[1], 1);

  ret = strdup ("ok");
  if (NULL == ret) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}

/* Send back an error of different lengths. */
static char *
debug_error (const char *subcmd, size_t argc, char *const *const argv)
{
  unsigned len;
  CLEANUP_FREE char *buf = NULL;

  if (argc != 1) {
  error:
    reply_with_error ("debug error: expecting one arg: length of error message");
    return NULL;
  }

  if (sscanf (argv[0], "%u", &len) != 1)
    goto error;

  if (len > 1000000) {
    reply_with_error ("debug error: length argument too large");
    return NULL;
  }

  buf = malloc (len + 1);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  memset (buf, 'a', len);
  buf[len] = '\0';

  /* So that the regression test can tell this is the true return path
   * from the function and not an actual error, we set errno to some
   * value that cannot be returned by any other error path.
   */
  reply_with_error_errno (EROFS, "%s", buf);
  return NULL;
}

/* Return binaries in the appliance.
 * See tests/regressions/rhbz727178.sh
 */
static char *
debug_binaries (const char *subcmd, size_t argc, char *const *const argv)
{
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;
  const char *cmd =
    "find / -xdev -type f -executable "
    "| xargs file -i "
    "| grep application/x-executable "
    "| gawk -F: '{print $1}'";

  r = command (&out, &err, "sh", "-c", cmd, NULL);
  if (r == -1) {
    reply_with_error ("find: %s", err);
    free (out);
    return NULL;
  }

  return out;
}

/* Run 'ldd' on a file from the appliance.
 * See tests/regressions/rhbz727178.sh
 */
static char *
debug_ldd (const char *subcmd, size_t argc, char *const *const argv)
{
  int r;
  char *out, *ret;
  CLEANUP_FREE char *err = NULL;

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
    return NULL;
  }

  /* Concatenate stdout and stderr in the result. */
  ret = realloc (out, strlen (out) + strlen (err) + 1);
  if (ret == NULL) {
    reply_with_perror ("realloc");
    free (out);
    return NULL;
  }

  strcat (ret, err);

  return ret;
}

/* List files in the appliance. */
static char *
debug_ls (const char *subcmd, size_t argc, char *const *const argv)
{
  const size_t len = guestfs_int_count_strings (argv);
  CLEANUP_FREE const char **cargv = NULL;
  size_t i;
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;

  cargv = malloc (sizeof (char *) * (len+3));
  if (cargv == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  cargv[0] = "ls";
  cargv[1] = "-a";
  for (i = 0; i < len; ++i)
    cargv[2+i] = argv[i];
  cargv[2+len] = NULL;

  r = commandv (&out, &err, (void *) cargv);
  if (r == -1) {
    reply_with_error ("ls: %s", err);
    free (out);
    return NULL;
  }

  return out;
}

/* List files in the appliance. */
static char *
debug_ll (const char *subcmd, size_t argc, char *const *const argv)
{
  const size_t len = guestfs_int_count_strings (argv);
  CLEANUP_FREE const char **cargv = NULL;
  size_t i;
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;

  cargv = malloc (sizeof (char *) * (len+3));
  if (cargv == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  cargv[0] = "ls";
  cargv[1] = "-la";
  for (i = 0; i < len; ++i)
    cargv[2+i] = argv[i];
  cargv[2+len] = NULL;

  r = commandv (&out, &err, (void *) cargv);
  if (r == -1) {
    reply_with_error ("ll: %s", err);
    free (out);
    return NULL;
  }

  return out;
}

/* Print something on the serial console.  Used to check that
 * debugging messages are being emitted.
 */
static char *
debug_print (const char *subcmd, size_t argc, char *const *const argv)
{
  size_t i;
  char *ret;

  for (i = 0; i < argc; ++i) {
    if (i > 0)
      fputc (' ', stderr);
    fprintf (stderr, "%s", argv[i]);
  }
  fputc ('\n', stderr);

  ret = strdup ("ok");
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}

/* Generate progress notification messages in order to test progress bars. */
static char *
debug_progress (const char *subcmd, size_t argc, char *const *const argv)
{
  uint64_t secs, rate = 0;
  char *ret;

  if (argc < 1) {
  error:
    reply_with_error ("progress: expecting one or more args: time in seconds [, rate in microseconds]");
    return NULL;
  }

  if (sscanf (argv[0], "%" SCNu64, &secs) != 1)
    goto error;
  if (secs == 0 || secs > 1000000) { /* RHBZ#816839 */
    reply_with_error ("progress: argument is 0, less than 0, or too large");
    return NULL;
  }

  if (argc >= 2) {
    if (sscanf (argv[1], "%" SCNu64, &rate) != 1)
      goto error;
    if (rate == 0 || rate > 1000000) {
      reply_with_error ("progress: rate is 0 or too large");
      return NULL;
    }
  }

  /* Note the inner loops go to '<= limit' because we want to ensure
   * that the final 100% completed message is set.
   */
  if (rate == 0) {              /* Ordinary rate-limited progress messages. */
    uint64_t tsecs = secs * 10; /* 1/10ths of seconds */
    uint64_t i;

    for (i = 1; i < tsecs+1; ++i) {
      usleep (100000);
      notify_progress (i, tsecs);
    }
  }
  else {                        /* Send messages at a given rate. */
    uint64_t usecs = secs * 1000000; /* microseconds */
    uint64_t i;
    struct timeval now;

    for (i = rate; i <= usecs; i += rate) {
      usleep (rate);
      gettimeofday (&now, NULL);
      notify_progress_no_ratelimit (i, usecs, &now);
    }
  }

  ret = strdup ("ok");
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
debug_core_pattern (const char *subcmd, size_t argc, char *const *const argv)
{
  if (argc < 1) {
    reply_with_error ("core_pattern: expecting a core pattern");
    return NULL;
  }

  const char *pattern = argv[0];
  const size_t pattern_len = strlen (pattern);

#define CORE_PATTERN "/proc/sys/kernel/core_pattern"
  int fd = open (CORE_PATTERN, O_WRONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: " CORE_PATTERN);
    return NULL;
  }
  if (write (fd, pattern, pattern_len) < (ssize_t) pattern_len) {
    reply_with_perror ("write: " CORE_PATTERN);
    close (fd);
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

/* Generate lots of debug messages.  Each line of output is 72
 * characters long (plus '\n'), so the total size of the output in
 * bytes is n*73.
 */
static char *
debug_spew (const char *subcmd, size_t argc, char *const *const argv)
{
  size_t i, n;
  char *ret;

  if (argc != 1) {
    reply_with_error ("spew: expecting number of lines <n>");
    return NULL;
  }

  if (sscanf (argv[0], "%zu", &n) != 1) {
    reply_with_error ("spew: could not parse number of lines '%s'", argv[0]);
    return NULL;
  }

  for (i = 0; i < n; ++i)
    fprintf (stderr,
             "abcdefghijklmnopqrstuvwxyz" /* 26 */
             "ABCDEFGHIJKLMNOPQRSTUVWXYZ" /* 52 */
             "01234567890123456789" /* 72 */
             "\n");

  ret = strdup ("ok");
  if (!ret) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;
}

static int
write_cb (void *fd_ptr, const void *buf, size_t len)
{
  const int fd = *(int *)fd_ptr;
  return xwrite (fd, buf, len);
}

/* This requires a non-upstream qemu patch.  See contrib/visualize-alignment/
 * directory in the libguestfs source tree.
 */
static char *
debug_qtrace (const char *subcmd, size_t argc, char *const *const argv)
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
  int fd = open (argv[0], O_RDONLY|O_DIRECT|O_CLOEXEC);
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
  CLEANUP_FREE void *buf = NULL;
  size_t i;

  /* For O_DIRECT, buffer must be aligned too (thanks Matt).
   * Note posix_memalign has this strange errno behaviour.
   */
  /* coverity[resource_leak] */
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
      return NULL;
    }

    if (read (fd, buf, QTRACE_SIZE) == -1) {
      reply_with_perror ("qtrace: %s: read", argv[0]);
      close (fd);
      return NULL;
    }
  }

  close (fd);

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

/* Used to test read and write speed. */
static char *
debug_device_speed (const char *subcmd, size_t argc, char *const *const argv)
{
  const char *device;
  int writing, err;
  unsigned secs;
  int64_t size, position, copied;
  CLEANUP_FREE void *buf = NULL;
  struct timeval now, end;
  ssize_t r;
  int fd;
  char *ret;

  if (argc != 3) {
  bad_args:
    reply_with_error ("device_speed <device> <r|w> <secs>");
    return NULL;
  }

  device = argv[0];
  if (STREQ (argv[1], "r") || STREQ (argv[1], "read"))
    writing = 0;
  else if (STREQ (argv[1], "w") || STREQ (argv[1], "write"))
    writing = 1;
  else
    goto bad_args;
  if (sscanf (argv[2], "%u", &secs) != 1)
    goto bad_args;

  /* Find the size of the device. */
  size = do_blockdev_getsize64 (device);
  if (size == -1)
    return NULL;

  if (size < BUFSIZ) {
    reply_with_error ("%s: device is too small", device);
    return NULL;
  }

  /* Because we're using O_DIRECT, the buffer must be aligned. */
  err = posix_memalign (&buf, 4096, BUFSIZ);
  if (err != 0) {
    reply_with_error_errno (err, "posix_memalign");
    return NULL;
  }

  /* Any non-zero data will do. */
  memset (buf, 100, BUFSIZ);

  fd = open (device, (writing ? O_WRONLY : O_RDONLY) | O_CLOEXEC | O_DIRECT);
  if (fd == -1) {
    reply_with_perror ("open: %s", device);
    return NULL;
  }

  /* Now we read or write to the device, wrapping around to the
   * beginning when we reach the end, and only stop when <secs>
   * seconds has elapsed.
   */
  gettimeofday (&end, NULL);
  end.tv_sec += secs;

  position = copied = 0;

  for (;;) {
    gettimeofday (&now, NULL);
    if (now.tv_sec > end.tv_sec ||
        (now.tv_sec == end.tv_sec && now.tv_usec > end.tv_usec))
      break;

    /* Because of O_DIRECT, only write whole, aligned buffers. */
  again:
    if (size - position < BUFSIZ) {
      position = 0;
      goto again;
    }

    /*
    if (verbose) {
      fprintf (stderr, "p%s (fd, buf, %d, %" PRIi64 ")\n",
               writing ? "write" : "read", BUFSIZ, position);
    }
    */

    if (writing) {
      r = pwrite (fd, buf, BUFSIZ, position);
      if (r == -1) {
        reply_with_perror ("write: %s", device);
        goto error;
      }
    }
    else {
      r = pread (fd, buf, BUFSIZ, position);
      if (r == -1) {
        reply_with_perror ("read: %s", device);
        goto error;
      }
      if (r == 0) {
        reply_with_error ("unexpected end of file while reading");
        goto error;
      }
    }
    position += BUFSIZ;
    copied += r;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", device);
    return NULL;
  }

  if (asprintf (&ret, "%" PRIi64, copied) == -1) {
    reply_with_perror ("asprintf");
    return NULL;
  }

  return ret;

 error:
  close (fd);
  return NULL;
}

/* Has one FileIn parameter. */
int
do_debug_upload (const char *filename, int mode)
{
  /* Not chrooted - this command lets you upload a file to anywhere
   * in the appliance.
   */
  int fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, mode);

  if (fd == -1) {
    const int err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("%s", filename);
    return -1;
  }

  int r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    const int err = errno;
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

/* This function is identical to debug_upload. */
/* Has one FileIn parameter. */
int
do_internal_upload (const char *filename, int mode)
{
  return do_debug_upload (filename, mode);
}

/* Internal function used only when testing
 * https://bugzilla.redhat.com/show_bug.cgi?id=914931
 */

static int
crash_cb (void *countv, const void *buf, size_t len)
{
  int *countp = countv;

  (*countp)--;
  sleep (1);

  if (*countp == 0)
    deliberately_cause_a_segfault ();

  return 0;
}

/* Has one FileIn parameter. */
int
do_internal_rhbz914931 (int count)
{
  int r;

  if (count <= 0 || count > 1000) {
    reply_with_error ("count out of range");
    return -1;
  }

  r = receive_file (crash_cb, &count);
  if (r == -1) {		/* write error */
    const int err = errno;
    cancel_receive ();
    errno = err;
    reply_with_error ("write error");
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    /* This error is ignored by the library since it initiated the
     * cancel.  Nevertheless we must send an error reply here.
     */
    reply_with_error ("file upload cancelled");
    return -1;
  }

  return 0;
}

static void
deliberately_cause_a_segfault (void)
{
  __builtin_trap ();
}
