/* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

#define _BSD_SOURCE /* for mkdtemp, usleep */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <dirent.h>
#include <signal.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#ifdef HAVE_ERRNO_H
#include <errno.h>
#endif

#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif

#ifdef HAVE_SYS_WAIT_H
#include <sys/wait.h>
#endif

#ifdef HAVE_SYS_SOCKET_H
#include <sys/socket.h>
#endif

#ifdef HAVE_SYS_UN_H
#include <sys/un.h>
#endif

#include <arpa/inet.h>
#include <netinet/in.h>

#include "c-ctype.h"
#include "glthread/lock.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int qemu_supports (guestfs_h *g, const char *option);

/* Add a string to the current command line. */
static void
incr_cmdline_size (guestfs_h *g)
{
  if (g->cmdline == NULL) {
    /* g->cmdline[0] is reserved for argv[0], set in guestfs_launch. */
    g->cmdline_size = 1;
    g->cmdline = safe_malloc (g, sizeof (char *));
    g->cmdline[0] = NULL;
  }

  g->cmdline_size++;
  g->cmdline = safe_realloc (g, g->cmdline, sizeof (char *) * g->cmdline_size);
}

static int
add_cmdline (guestfs_h *g, const char *str)
{
  if (g->state != CONFIG) {
    error (g,
        _("command line cannot be altered after qemu subprocess launched"));
    return -1;
  }

  incr_cmdline_size (g);
  g->cmdline[g->cmdline_size-1] = safe_strdup (g, str);
  return 0;
}

int
guestfs__config (guestfs_h *g,
                 const char *qemu_param, const char *qemu_value)
{
  if (qemu_param[0] != '-') {
    error (g, _("guestfs_config: parameter must begin with '-' character"));
    return -1;
  }

  /* A bit fascist, but the user will probably break the extra
   * parameters that we add if they try to set any of these.
   */
  if (STREQ (qemu_param, "-kernel") ||
      STREQ (qemu_param, "-initrd") ||
      STREQ (qemu_param, "-nographic") ||
      STREQ (qemu_param, "-serial") ||
      STREQ (qemu_param, "-full-screen") ||
      STREQ (qemu_param, "-std-vga") ||
      STREQ (qemu_param, "-vnc")) {
    error (g, _("guestfs_config: parameter '%s' isn't allowed"), qemu_param);
    return -1;
  }

  if (add_cmdline (g, qemu_param) != 0) return -1;

  if (qemu_value != NULL) {
    if (add_cmdline (g, qemu_value) != 0) return -1;
  }

  return 0;
}

int
guestfs__add_drive_with_if (guestfs_h *g, const char *filename,
                            const char *drive_if)
{
  size_t len = strlen (filename) + 64;
  char buf[len];

  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }

  /* cache=off improves reliability in the event of a host crash.
   *
   * However this option causes qemu to try to open the file with
   * O_DIRECT.  This fails on some filesystem types (notably tmpfs).
   * So we check if we can open the file with or without O_DIRECT,
   * and use cache=off (or not) accordingly.
   *
   * This test also checks for the presence of the file, which
   * is a documented semantic of this interface.
   */
  int fd = open (filename, O_RDONLY|O_DIRECT);
  if (fd >= 0) {
    close (fd);
    snprintf (buf, len, "file=%s,cache=off,if=%s", filename, drive_if);
  } else {
    fd = open (filename, O_RDONLY);
    if (fd >= 0) {
      close (fd);
      snprintf (buf, len, "file=%s,if=%s", filename, drive_if);
    } else {
      perrorf (g, "%s", filename);
      return -1;
    }
  }

  return guestfs__config (g, "-drive", buf);
}

int
guestfs__add_drive_ro_with_if (guestfs_h *g, const char *filename,
                               const char *drive_if)
{
  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  size_t len = strlen (filename) + 64;
  char buf[len];

  snprintf (buf, len, "file=%s,snapshot=on,if=%s", filename, drive_if);

  return guestfs__config (g, "-drive", buf);
}

int
guestfs__add_drive (guestfs_h *g, const char *filename)
{
  return guestfs__add_drive_with_if (g, filename, DRIVE_IF);
}

int
guestfs__add_drive_ro (guestfs_h *g, const char *filename)
{
  return guestfs__add_drive_ro_with_if (g, filename, DRIVE_IF);
}

int
guestfs__add_cdrom (guestfs_h *g, const char *filename)
{
  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  return guestfs__config (g, "-cdrom", filename);
}

static int is_openable (guestfs_h *g, const char *path, int flags);
static void print_cmdline (guestfs_h *g);

int
guestfs__launch (guestfs_h *g)
{
  int r;
  int wfd[2], rfd[2];
  int tries;
  char unixsock[256];
  struct sockaddr_un addr;

  /* Configured? */
  if (!g->cmdline) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  if (g->state != CONFIG) {
    error (g, _("the libguestfs handle has already been launched"));
    return -1;
  }

  /* Start the clock ... */
  gettimeofday (&g->launch_t, NULL);

  /* Make the temporary directory. */
  if (!g->tmpdir) {
    const char *tmpdir = guestfs___tmpdir ();
    char dir_template[strlen (tmpdir) + 32];
    sprintf (dir_template, "%s/libguestfsXXXXXX", tmpdir);

    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), dir_template);
      goto cleanup0;
    }
  }

  /* Allow anyone to read the temporary directory.  The socket in this
   * directory won't be readable but anyone can see it exists if they
   * want. (RHBZ#610880).
   */
  if (chmod (g->tmpdir, 0755) == -1)
    fprintf (stderr, "chmod: %s: %m (ignored)\n", g->tmpdir);

  /* Locate and/or build the appliance. */
  char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  if (guestfs___build_appliance (g, &kernel, &initrd, &appliance) == -1)
    return -1;

  if (g->verbose)
    guestfs___print_timestamped_message (g, "begin testing qemu features");

  /* Get qemu help text and version. */
  if (qemu_supports (g, NULL) == -1)
    goto cleanup0;

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  snprintf (unixsock, sizeof unixsock, "%s/sock", g->tmpdir);
  unlink (unixsock);

  g->sock = socket (AF_UNIX, SOCK_STREAM, 0);
  if (g->sock == -1) {
    perrorf (g, "socket");
    goto cleanup0;
  }

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup0;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, unixsock, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  if (bind (g->sock, &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup0;
  }

  if (listen (g->sock, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup0;
  }

  if (!g->direct) {
    if (pipe (wfd) == -1 || pipe (rfd) == -1) {
      perrorf (g, "pipe");
      goto cleanup0;
    }
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "finished testing qemu features");

  r = fork ();
  if (r == -1) {
    perrorf (g, "fork");
    if (!g->direct) {
      close (wfd[0]);
      close (wfd[1]);
      close (rfd[0]);
      close (rfd[1]);
    }
    goto cleanup0;
  }

  if (r == 0) {			/* Child (qemu). */
    char buf[256];

    /* Set up the full command line.  Do this in the subprocess so we
     * don't need to worry about cleaning up.
     */
    g->cmdline[0] = g->qemu;

    /* qemu sometimes needs this option to enable hardware
     * virtualization, but some versions of 'qemu-kvm' will use KVM
     * regardless (even where this option appears in the help text).
     * It is rumoured that there are versions of qemu where supplying
     * this option when hardware virtualization is not available will
     * cause qemu to fail, so we we have to check at least that
     * /dev/kvm is openable.  That's not reliable, since /dev/kvm
     * might be openable by qemu but not by us (think: SELinux) in
     * which case the user would not get hardware virtualization,
     * although at least shouldn't fail.  A giant clusterfuck with the
     * qemu command line, again.
     */
    if (qemu_supports (g, "-enable-kvm") &&
        is_openable (g, "/dev/kvm", O_RDWR))
      add_cmdline (g, "-enable-kvm");

    /* Newer versions of qemu (from around 2009/12) changed the
     * behaviour of monitors so that an implicit '-monitor stdio' is
     * assumed if we are in -nographic mode and there is no other
     * -monitor option.  Only a single stdio device is allowed, so
     * this broke the '-serial stdio' option.  There is a new flag
     * called -nodefaults which gets rid of all this default crud, so
     * let's use that to avoid this and any future surprises.
     */
    if (qemu_supports (g, "-nodefaults"))
      add_cmdline (g, "-nodefaults");

    add_cmdline (g, "-nographic");

    snprintf (buf, sizeof buf, "%d", g->memsize);
    add_cmdline (g, "-m");
    add_cmdline (g, buf);

    /* Force exit instead of reboot on panic */
    add_cmdline (g, "-no-reboot");

    /* These options recommended by KVM developers to improve reliability. */
    if (qemu_supports (g, "-no-hpet"))
      add_cmdline (g, "-no-hpet");

    if (qemu_supports (g, "-rtc-td-hack"))
      add_cmdline (g, "-rtc-td-hack");

    /* Create the virtio serial bus. */
    add_cmdline (g, "-device");
    add_cmdline (g, "virtio-serial");

#if 0
    /* Use virtio-console (a variant form of virtio-serial) for the
     * guest's serial console.
     */
    add_cmdline (g, "-chardev");
    add_cmdline (g, "stdio,id=console");
    add_cmdline (g, "-device");
    add_cmdline (g, "virtconsole,chardev=console,name=org.libguestfs.console.0");
#else
    /* When the above works ...  until then: */
    add_cmdline (g, "-serial");
    add_cmdline (g, "stdio");
#endif

    /* Set up virtio-serial for the communications channel. */
    add_cmdline (g, "-chardev");
    snprintf (buf, sizeof buf, "socket,path=%s,id=channel0", unixsock);
    add_cmdline (g, buf);
    add_cmdline (g, "-device");
    add_cmdline (g, "virtserialport,chardev=channel0,name=org.libguestfs.channel.0");

    /* Enable user networking. */
    if (g->enable_network) {
      add_cmdline (g, "-netdev");
      add_cmdline (g, "user,id=usernet");
      add_cmdline (g, "-device");
      add_cmdline (g, NET_IF ",netdev=usernet");
    }

#define LINUX_CMDLINE							\
    "panic=1 "         /* force kernel to panic if daemon exits */	\
    "console=ttyS0 "   /* serial console */				\
    "udevtimeout=300 " /* good for very slow systems (RHBZ#480319) */	\
    "noapic "          /* workaround for RHBZ#502058 - ok if not SMP */ \
    "acpi=off "        /* we don't need ACPI, turn it off */		\
    "printk.time=1 "   /* display timestamp before kernel messages */   \
    "cgroup_disable=memory " /* saves us about 5 MB of RAM */

    /* Linux kernel command line. */
    snprintf (buf, sizeof buf,
              LINUX_CMDLINE
              "%s "             /* (selinux) */
              "%s "             /* (verbose) */
              "TERM=%s "        /* (TERM environment variable) */
              "%s",             /* (append) */
              g->selinux ? "selinux=1 enforcing=0" : "selinux=0",
              g->verbose ? "guestfs_verbose=1" : "",
              getenv ("TERM") ? : "linux",
              g->append ? g->append : "");

    add_cmdline (g, "-kernel");
    add_cmdline (g, kernel);
    add_cmdline (g, "-initrd");
    add_cmdline (g, initrd);
    add_cmdline (g, "-append");
    add_cmdline (g, buf);

    /* Add the ext2 appliance drive (last of all). */
    if (appliance) {
      const char *cachemode = "";
      if (qemu_supports (g, "cache=")) {
        if (qemu_supports (g, "unsafe"))
          cachemode = ",cache=unsafe";
        else if (qemu_supports (g, "writeback"))
          cachemode = ",cache=writeback";
      }

      char buf2[PATH_MAX + 64];
      add_cmdline (g, "-drive");
      snprintf (buf2, sizeof buf2, "file=%s,snapshot=on,if=" DRIVE_IF "%s",
                appliance, cachemode);
      add_cmdline (g, buf2);
    }

    /* Finish off the command line. */
    incr_cmdline_size (g);
    g->cmdline[g->cmdline_size-1] = NULL;

    if (g->verbose)
      print_cmdline (g);

    if (!g->direct) {
      /* Set up stdin, stdout. */
      close (0);
      close (1);
      close (wfd[1]);
      close (rfd[0]);

      if (dup (wfd[0]) == -1) {
      dup_failed:
        perror ("dup failed");
        _exit (EXIT_FAILURE);
      }
      if (dup (rfd[1]) == -1)
        goto dup_failed;

      close (wfd[0]);
      close (rfd[1]);
    }

#if 0
    /* Set up a new process group, so we can signal this process
     * and all subprocesses (eg. if qemu is really a shell script).
     */
    setpgid (0, 0);
#endif

    setenv ("LC_ALL", "C", 1);

    execv (g->qemu, g->cmdline); /* Run qemu. */
    perror (g->qemu);
    _exit (EXIT_FAILURE);
  }

  /* Parent (library). */
  g->pid = r;

  free (kernel);
  kernel = NULL;
  free (initrd);
  initrd = NULL;

  /* Fork the recovery process off which will kill qemu if the parent
   * process fails to do so (eg. if the parent segfaults).
   */
  g->recoverypid = -1;
  if (g->recovery_proc) {
    r = fork ();
    if (r == 0) {
      pid_t qemu_pid = g->pid;
      pid_t parent_pid = getppid ();

      /* Writing to argv is hideously complicated and error prone.  See:
       * http://anoncvs.postgresql.org/cvsweb.cgi/pgsql/src/backend/utils/misc/ps_status.c?rev=1.33.2.1;content-type=text%2Fplain
       */

      /* Loop around waiting for one or both of the other processes to
       * disappear.  It's fair to say this is very hairy.  The PIDs that
       * we are looking at might be reused by another process.  We are
       * effectively polling.  Is the cure worse than the disease?
       */
      for (;;) {
        if (kill (qemu_pid, 0) == -1) /* qemu's gone away, we aren't needed */
          _exit (EXIT_SUCCESS);
        if (kill (parent_pid, 0) == -1) {
          /* Parent's gone away, qemu still around, so kill qemu. */
          kill (qemu_pid, 9);
          _exit (EXIT_SUCCESS);
        }
        sleep (2);
      }
    }

    /* Don't worry, if the fork failed, this will be -1.  The recovery
     * process isn't essential.
     */
    g->recoverypid = r;
  }

  if (!g->direct) {
    /* Close the other ends of the pipe. */
    close (wfd[0]);
    close (rfd[1]);

    if (fcntl (wfd[1], F_SETFL, O_NONBLOCK) == -1 ||
        fcntl (rfd[0], F_SETFL, O_NONBLOCK) == -1) {
      perrorf (g, "fcntl");
      goto cleanup1;
    }

    g->fd[0] = wfd[1];		/* stdin of child */
    g->fd[1] = rfd[0];		/* stdout of child */
  } else {
    g->fd[0] = open ("/dev/null", O_RDWR);
    if (g->fd[0] == -1) {
      perrorf (g, "open /dev/null");
      goto cleanup1;
    }
    g->fd[1] = dup (g->fd[0]);
    if (g->fd[1] == -1) {
      perrorf (g, "dup");
      close (g->fd[0]);
      goto cleanup1;
    }
  }

  g->state = LAUNCHING;

  /* Wait for qemu to start and to connect back to us via
   * virtio-serial and send the GUESTFS_LAUNCH_FLAG message.
   */
  r = guestfs___accept_from_daemon (g);
  if (r == -1)
    goto cleanup1;

  close (g->sock); /* Close the listening socket. */
  g->sock = r; /* This is the accepted data socket. */

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup1;
  }

  uint32_t size;
  void *buf = NULL;
  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) return -1;

  if (size != GUESTFS_LAUNCH_FLAG) {
    error (g, _("guestfs_launch failed, see earlier error messages"));
    goto cleanup1;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "appliance is up");

  /* This is possible in some really strange situations, such as
   * guestfsd starts up OK but then qemu immediately exits.  Check for
   * it because the caller is probably expecting to be able to send
   * commands after this function returns.
   */
  if (g->state != READY) {
    error (g, _("qemu launched and contacted daemon, but state != READY"));
    goto cleanup1;
  }

  return 0;

 cleanup1:
  if (!g->direct) {
    close (wfd[1]);
    close (rfd[0]);
  }
  if (g->pid > 0) kill (g->pid, 9);
  if (g->recoverypid > 0) kill (g->recoverypid, 9);
  waitpid (g->pid, NULL, 0);
  if (g->recoverypid > 0) waitpid (g->recoverypid, NULL, 0);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->pid = 0;
  g->recoverypid = 0;
  memset (&g->launch_t, 0, sizeof g->launch_t);

 cleanup0:
  if (g->sock >= 0) {
    close (g->sock);
    g->sock = -1;
  }
  g->state = CONFIG;
  free (kernel);
  free (initrd);
  free (appliance);
  return -1;
}

const char *
guestfs___tmpdir (void)
{
  const char *tmpdir;

#ifdef P_tmpdir
  tmpdir = P_tmpdir;
#else
  tmpdir = "/tmp";
#endif

  const char *t = getenv ("TMPDIR");
  if (t) tmpdir = t;

  return tmpdir;
}

/* This function is used to print the qemu command line before it gets
 * executed, when in verbose mode.
 */
static void
print_cmdline (guestfs_h *g)
{
  int i = 0;
  int needs_quote;

  while (g->cmdline[i]) {
    if (g->cmdline[i][0] == '-') /* -option starts a new line */
      fprintf (stderr, " \\\n   ");

    if (i > 0) fputc (' ', stderr);

    /* Does it need shell quoting?  This only deals with simple cases. */
    needs_quote = strcspn (g->cmdline[i], " ") != strlen (g->cmdline[i]);

    if (needs_quote) fputc ('\'', stderr);
    fprintf (stderr, "%s", g->cmdline[i]);
    if (needs_quote) fputc ('\'', stderr);
    i++;
  }

  fputc ('\n', stderr);
}

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
static int64_t
timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

void
guestfs___print_timestamped_message (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int err;
  struct timeval tv;

  va_start (args, fs);
  err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  gettimeofday (&tv, NULL);

  fprintf (stderr, "[%05" PRIi64 "ms] %s\n",
           timeval_diff (&g->launch_t, &tv), msg);

  free (msg);
}

static int read_all (guestfs_h *g, FILE *fp, char **ret);

/* Test qemu binary (or wrapper) runs, and do 'qemu -help' and
 * 'qemu -version' so we know what options this qemu supports and
 * the version.
 */
static int
test_qemu (guestfs_h *g)
{
  char cmd[1024];
  FILE *fp;

  snprintf (cmd, sizeof cmd, "LC_ALL=C '%s' -nographic -help", g->qemu);

  fp = popen (cmd, "r");
  /* qemu -help should always work (qemu -version OTOH wasn't
   * supported by qemu 0.9).  If this command doesn't work then it
   * probably indicates that the qemu binary is missing.
   */
  if (!fp) {
    /* XXX This error is never printed, even if the qemu binary
     * doesn't exist.  Why?
     */
  error:
    perrorf (g, _("%s: command failed: If qemu is located on a non-standard path, try setting the LIBGUESTFS_QEMU environment variable."), cmd);
    return -1;
  }

  if (read_all (g, fp, &g->qemu_help) == -1)
    goto error;

  if (pclose (fp) == -1)
    goto error;

  snprintf (cmd, sizeof cmd, "LC_ALL=C '%s' -nographic -version 2>/dev/null",
	    g->qemu);

  fp = popen (cmd, "r");
  if (fp) {
    /* Intentionally ignore errors. */
    read_all (g, fp, &g->qemu_version);
    pclose (fp);
  }

  return 0;
}

static int
read_all (guestfs_h *g, FILE *fp, char **ret)
{
  int r, n = 0;
  char *p;

 again:
  if (feof (fp)) {
    *ret = safe_realloc (g, *ret, n + 1);
    (*ret)[n] = '\0';
    return n;
  }

  *ret = safe_realloc (g, *ret, n + BUFSIZ);
  p = &(*ret)[n];
  r = fread (p, 1, BUFSIZ, fp);
  if (ferror (fp)) {
    perrorf (g, "read");
    return -1;
  }
  n += r;
  goto again;
}

/* Test if option is supported by qemu command line (just by grepping
 * the help text).
 *
 * The first time this is used, it has to run the external qemu
 * binary.  If that fails, it returns -1.
 *
 * To just do the first-time run of the qemu binary, call this with
 * option == NULL, in which case it will return -1 if there was an
 * error doing that.
 */
static int
qemu_supports (guestfs_h *g, const char *option)
{
  if (!g->qemu_help) {
    if (test_qemu (g) == -1)
      return -1;
  }

  if (option == NULL)
    return 1;

  return strstr (g->qemu_help, option) != NULL;
}

/* Check if a file can be opened. */
static int
is_openable (guestfs_h *g, const char *path, int flags)
{
  int fd = open (path, flags);
  if (fd == -1) {
    if (g->verbose)
      perror (path);
    return 0;
  }
  close (fd);
  return 1;
}

/* You had to call this function after launch in versions <= 1.0.70,
 * but it is now a no-op.
 */
int
guestfs__wait_ready (guestfs_h *g)
{
  if (g->state != READY)  {
    error (g, _("qemu has not been launched yet"));
    return -1;
  }

  return 0;
}

int
guestfs__kill_subprocess (guestfs_h *g)
{
  if (g->state == CONFIG) {
    error (g, _("no subprocess to kill"));
    return -1;
  }

  if (g->verbose)
    fprintf (stderr, "sending SIGTERM to process %d\n", g->pid);

  if (g->pid > 0) kill (g->pid, SIGTERM);
  if (g->recoverypid > 0) kill (g->recoverypid, 9);

  return 0;
}

/* Access current state. */
int
guestfs__is_config (guestfs_h *g)
{
  return g->state == CONFIG;
}

int
guestfs__is_launching (guestfs_h *g)
{
  return g->state == LAUNCHING;
}

int
guestfs__is_ready (guestfs_h *g)
{
  return g->state == READY;
}

int
guestfs__is_busy (guestfs_h *g)
{
  return g->state == BUSY;
}

int
guestfs__get_state (guestfs_h *g)
{
  return g->state;
}
