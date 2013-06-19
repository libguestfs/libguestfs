/* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
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
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <pcre.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Compile all the regular expressions once when the shared library is
 * loaded.  PCRE is thread safe so we're supposedly OK here if
 * multiple threads call into the libguestfs API functions below
 * simultaneously.
 */
static pcre *re_major_minor;

static void compile_regexps (void) __attribute__((constructor));
static void free_regexps (void) __attribute__((destructor));

static void
compile_regexps (void)
{
  const char *err;
  int offset;

#define COMPILE(re,pattern,options)                                     \
  do {                                                                  \
    re = pcre_compile ((pattern), (options), &err, &offset, NULL);      \
    if (re == NULL) {                                                   \
      ignore_value (write (2, err, strlen (err)));                      \
      abort ();                                                         \
    }                                                                   \
  } while (0)

  COMPILE (re_major_minor, "(\\d+)\\.(\\d+)", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_major_minor);
}

static int is_openable (guestfs_h *g, const char *path, int flags);
static char *make_appliance_dev (guestfs_h *g, int virtio_scsi);
static void print_qemu_command_line (guestfs_h *g, char **argv);
static int qemu_supports (guestfs_h *g, const char *option);
static int qemu_supports_device (guestfs_h *g, const char *device_name);
static int qemu_supports_virtio_scsi (guestfs_h *g);
static char *qemu_drive_param (guestfs_h *g, const struct drive *drv, size_t index);

/* Functions to build up the qemu command line.  These are only run
 * in the child process so no clean-up is required.
 */
static void
alloc_cmdline (guestfs_h *g)
{
  g->app.cmdline_size = 1;
  g->app.cmdline = safe_malloc (g, sizeof (char *));
  g->app.cmdline[0] = g->qemu;
}

static void
incr_cmdline_size (guestfs_h *g)
{
  g->app.cmdline_size++;
  g->app.cmdline =
    safe_realloc (g, g->app.cmdline, sizeof (char *) * g->app.cmdline_size);
}

static void
add_cmdline (guestfs_h *g, const char *str)
{
  incr_cmdline_size (g);
  g->app.cmdline[g->app.cmdline_size-1] = safe_strdup (g, str);
}

/* Like 'add_cmdline' but allowing a shell-quoted string of zero or
 * more options.  XXX The unquoting is not very clever.
 */
static void
add_cmdline_shell_unquoted (guestfs_h *g, const char *options)
{
  char quote;
  const char *startp, *endp, *nextp;

  while (*options) {
    quote = *options;
    if (quote == '\'' || quote == '"')
      startp = options+1;
    else {
      startp = options;
      quote = ' ';
    }

    endp = strchr (options, quote);
    if (endp == NULL) {
      if (quote != ' ') {
        fprintf (stderr,
                 _("unclosed quote character (%c) in command line near: %s"),
                 quote, options);
        _exit (EXIT_FAILURE);
      }
      endp = options + strlen (options);
    }

    if (quote == ' ') {
      if (endp[0] == '\0')
        nextp = endp;
      else
        nextp = endp+1;
    }
    else {
      if (!endp[1])
        nextp = endp+1;
      else if (endp[1] == ' ')
        nextp = endp+2;
      else {
        fprintf (stderr, _("cannot parse quoted string near: %s"), options);
        _exit (EXIT_FAILURE);
      }
    }
    while (*nextp && *nextp == ' ')
      nextp++;

    incr_cmdline_size (g);
    g->app.cmdline[g->app.cmdline_size-1] =
      safe_strndup (g, startp, endp-startp);

    options = nextp;
  }
}

static int
launch_appliance (guestfs_h *g, const char *arg)
{
  int r;
  int wfd[2], rfd[2];
  char guestfsd_sock[256];
  struct sockaddr_un addr;
  CLEANUP_FREE char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  int has_appliance_drive;
  CLEANUP_FREE char *appliance_dev = NULL;
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;

  /* At present you must add drives before starting the appliance.  In
   * future when we enable hotplugging you won't need to do this.
   */
  if (!g->nr_drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  guestfs___launch_send_progress (g, 0);

  TRACE0 (launch_build_appliance_start);

  /* Locate and/or build the appliance. */
  if (guestfs___build_appliance (g, &kernel, &initrd, &appliance) == -1)
    return -1;
  has_appliance_drive = appliance != NULL;

  TRACE0 (launch_build_appliance_end);

  guestfs___launch_send_progress (g, 3);

  if (g->verbose)
    guestfs___print_timestamped_message (g, "begin testing qemu features");

  /* Get qemu help text and version. */
  if (qemu_supports (g, NULL) == -1)
    goto cleanup0;

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  snprintf (guestfsd_sock, sizeof guestfsd_sock, "%s/guestfsd.sock", g->tmpdir);
  unlink (guestfsd_sock);

  g->sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (g->sock == -1) {
    perrorf (g, "socket");
    goto cleanup0;
  }

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup0;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, guestfsd_sock, UNIX_PATH_MAX);
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
    int virtio_scsi = qemu_supports_virtio_scsi (g);
    struct qemu_param *qp;

    /* Set up the full command line.  Do this in the subprocess so we
     * don't need to worry about cleaning up.
     */
    alloc_cmdline (g);

    /* CVE-2011-4127 mitigation: Disable SCSI ioctls on virtio-blk
     * devices.  The -global option must exist, but you can pass any
     * strings to it so we don't need to check for the specific virtio
     * feature.
     */
    if (qemu_supports (g, "-global")) {
      add_cmdline (g, "-global");
      add_cmdline (g, "virtio-blk-pci.scsi=off");
    }

    if (qemu_supports (g, "-nodefconfig"))
      add_cmdline (g, "-nodefconfig");

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

    /* Add drives */
    struct drive *drv;
    size_t i;

    if (virtio_scsi) {
      /* Create the virtio-scsi bus. */
      add_cmdline (g, "-device");
      add_cmdline (g, "virtio-scsi-pci,id=scsi");
    }

    ITER_DRIVES (g, i, drv) {
      /* Construct the final -drive parameter. */
      CLEANUP_FREE char *buf = qemu_drive_param (g, drv, i);

      add_cmdline (g, "-drive");
      add_cmdline (g, buf);

      if (virtio_scsi && drv->iface == NULL) {
        char buf2[64];
        snprintf (buf2, sizeof buf2, "scsi-hd,drive=hd%zu", i);
        add_cmdline (g, "-device");
        add_cmdline (g, buf2);
      }
    }

    /* Add the ext2 appliance drive (after all the drives). */
    if (has_appliance_drive) {
      const char *cachemode = "";
      if (qemu_supports (g, "cache=")) {
        if (qemu_supports (g, "unsafe"))
          cachemode = ",cache=unsafe";
        else if (qemu_supports (g, "writeback"))
          cachemode = ",cache=writeback";
      }

      size_t buf2_len = strlen (appliance) + 64;
      char buf2[buf2_len];
      add_cmdline (g, "-drive");
      snprintf (buf2, buf2_len, "file=%s,snapshot=on,id=appliance,if=%s%s",
                appliance, virtio_scsi ? "none" : "virtio", cachemode);
      add_cmdline (g, buf2);

      if (virtio_scsi) {
        add_cmdline (g, "-device");
        add_cmdline (g, "scsi-hd,drive=appliance");
      }

      appliance_dev = make_appliance_dev (g, virtio_scsi);
    }

    /* The qemu -machine option (added 2010-12) is a bit more sane
     * since it falls back through various different acceleration
     * modes, so try that first (thanks Markus Armbruster).
     */
    if (qemu_supports (g, "-machine")) {
      add_cmdline (g, "-machine");
      add_cmdline (g, "accel=kvm:tcg");
    } else {
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
          is_openable (g, "/dev/kvm", O_RDWR|O_CLOEXEC))
        add_cmdline (g, "-enable-kvm");
    }

    if (g->smp > 1) {
      snprintf (buf, sizeof buf, "%d", g->smp);
      add_cmdline (g, "-smp");
      add_cmdline (g, buf);
    }

    snprintf (buf, sizeof buf, "%d", g->memsize);
    add_cmdline (g, "-m");
    add_cmdline (g, buf);

    /* Force exit instead of reboot on panic */
    add_cmdline (g, "-no-reboot");

    /* These options recommended by KVM developers to improve reliability. */
#ifndef __arm__
    /* qemu-system-arm advertises the -no-hpet option but if you try
     * to use it, it usefully says:
     *   "Option no-hpet not supported for this target".
     * Cheers qemu developers.  How many years have we been asking for
     * capabilities?  Could be 3 or 4 years, I forget.
     */
    if (qemu_supports (g, "-no-hpet"))
      add_cmdline (g, "-no-hpet");
#endif

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

    if (qemu_supports_device (g, "Serial Graphics Adapter")) {
      /* Use sgabios instead of vgabios.  This means we'll see BIOS
       * messages on the serial port, and also works around this bug
       * in qemu 1.1.0:
       * https://bugs.launchpad.net/qemu/+bug/1021649
       * QEmu has included sgabios upstream since just before 1.0.
       */
      add_cmdline (g, "-device");
      add_cmdline (g, "sga");
    }

    /* Set up virtio-serial for the communications channel. */
    add_cmdline (g, "-chardev");
    snprintf (buf, sizeof buf, "socket,path=%s,id=channel0", guestfsd_sock);
    add_cmdline (g, buf);
    add_cmdline (g, "-device");
    add_cmdline (g, "virtserialport,chardev=channel0,name=org.libguestfs.channel.0");

#ifdef VALGRIND_DAEMON
    /* Set up virtio-serial channel for valgrind messages. */
    add_cmdline (g, "-chardev");
    snprintf (buf, sizeof buf, "file,path=%s/valgrind.log.%d,id=valgrind",
              VALGRIND_LOG_PATH, getpid ());
    add_cmdline (g, buf);
    add_cmdline (g, "-device");
    add_cmdline (g, "virtserialport,chardev=valgrind,name=org.libguestfs.valgrind");
#endif

    /* Enable user networking. */
    if (g->enable_network) {
      add_cmdline (g, "-netdev");
      add_cmdline (g, "user,id=usernet,net=169.254.0.0/16");
      add_cmdline (g, "-device");
      add_cmdline (g, "virtio-net-pci,netdev=usernet");
    }

    add_cmdline (g, "-kernel");
    add_cmdline (g, kernel);
    add_cmdline (g, "-initrd");
    add_cmdline (g, initrd);

    add_cmdline (g, "-append");
    CLEANUP_FREE char *cmdline =
      guestfs___appliance_command_line (g, appliance_dev, 0);
    add_cmdline (g, cmdline);

    /* Note: custom command line parameters must come last so that
     * qemu -set parameters can modify previously added options.
     */

    /* Add the extra options for the qemu command line specified
     * at configure time.
     */
    if (STRNEQ (QEMU_OPTIONS, ""))
      add_cmdline_shell_unquoted (g, QEMU_OPTIONS);

    /* Add any qemu parameters. */
    for (qp = g->qemu_params; qp; qp = qp->next) {
      add_cmdline (g, qp->qemu_param);
      if (qp->qemu_value)
        add_cmdline (g, qp->qemu_value);
    }

    /* Finish off the command line. */
    incr_cmdline_size (g);
    g->app.cmdline[g->app.cmdline_size-1] = NULL;

    if (!g->direct) {
      /* Set up stdin, stdout, stderr. */
      close (0);
      close (1);
      close (wfd[1]);
      close (rfd[0]);

      /* Stdin. */
      if (dup (wfd[0]) == -1) {
      dup_failed:
        perror ("dup failed");
        _exit (EXIT_FAILURE);
      }
      /* Stdout. */
      if (dup (rfd[1]) == -1)
        goto dup_failed;

      /* Particularly since qemu 0.15, qemu spews all sorts of debug
       * information on stderr.  It is useful to both capture this and
       * not confuse casual users, so send stderr to the pipe as well.
       */
      close (2);
      if (dup (rfd[1]) == -1)
        goto dup_failed;

      close (wfd[0]);
      close (rfd[1]);
    }

    /* Dump the command line (after setting up stderr above). */
    if (g->verbose)
      print_qemu_command_line (g, g->app.cmdline);

    /* Put qemu in a new process group. */
    if (g->pgroup)
      setpgid (0, 0);

    setenv ("LC_ALL", "C", 1);

    TRACE0 (launch_run_qemu);

    execv (g->qemu, g->app.cmdline); /* Run qemu. */
    perror (g->qemu);
    _exit (EXIT_FAILURE);
  }

  /* Parent (library). */
  g->app.pid = r;

  /* Fork the recovery process off which will kill qemu if the parent
   * process fails to do so (eg. if the parent segfaults).
   */
  g->app.recoverypid = -1;
  if (g->recovery_proc) {
    r = fork ();
    if (r == 0) {
      int i, fd, max_fd;
      struct sigaction sa;
      pid_t qemu_pid = g->app.pid;
      pid_t parent_pid = getppid ();

      /* Remove all signal handlers.  See the justification here:
       * https://www.redhat.com/archives/libvir-list/2008-August/msg00303.html
       * We don't mask signal handlers yet, so this isn't completely
       * race-free, but better than not doing it at all.
       */
      memset (&sa, 0, sizeof sa);
      sa.sa_handler = SIG_DFL;
      sa.sa_flags = 0;
      sigemptyset (&sa.sa_mask);
      for (i = 1; i < NSIG; ++i)
        sigaction (i, &sa, NULL);

      /* Close all other file descriptors.  This ensures that we don't
       * hold open (eg) pipes from the parent process.
       */
      max_fd = sysconf (_SC_OPEN_MAX);
      if (max_fd == -1)
        max_fd = 1024;
      if (max_fd > 65536)
        max_fd = 65536; /* bound the amount of work we do here */
      for (fd = 0; fd < max_fd; ++fd)
        close (fd);

      /* It would be nice to be able to put this in the same process
       * group as qemu (ie. setpgid (0, qemu_pid)).  However this is
       * not possible because we don't have any guarantee here that
       * the qemu process has started yet.
       */
      if (g->pgroup)
        setpgid (0, 0);

      /* Writing to argv is hideously complicated and error prone.  See:
       * http://git.postgresql.org/gitweb/?p=postgresql.git;a=blob;f=src/backend/utils/misc/ps_status.c;hb=HEAD
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
    g->app.recoverypid = r;
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
    wfd[1] = rfd[0] = -1;
  }

  g->state = LAUNCHING;

  /* Wait for qemu to start and to connect back to us via
   * virtio-serial and send the GUESTFS_LAUNCH_FLAG message.
   */
  r = guestfs___accept_from_daemon (g);
  if (r == -1)
    goto cleanup1;

  /* NB: We reach here just because qemu has opened the socket.  It
   * does not mean the daemon is up until we read the
   * GUESTFS_LAUNCH_FLAG below.  Failures in qemu startup can still
   * happen even if we reach here, even early failures like not being
   * able to open a drive.
   */

  /* Close the listening socket. */
  if (close (g->sock) != 0) {
    perrorf (g, "close: listening socket");
    close (r);
    g->sock = -1;
    goto cleanup1;
  }
  g->sock = r; /* This is the accepted data socket. */

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup1;
  }

  r = guestfs___recv_from_daemon (g, &size, &buf);

  if (r == -1) {
    guestfs___launch_failed_error (g);
    goto cleanup1;
  }

  if (size != GUESTFS_LAUNCH_FLAG) {
    guestfs___launch_failed_error (g);
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

  TRACE0 (launch_end);

  guestfs___launch_send_progress (g, 12);

  if (has_appliance_drive)
    guestfs___add_dummy_appliance_drive (g);

  return 0;

 cleanup1:
  if (!g->direct) {
    if (wfd[1] >= 0) close (wfd[1]);
    if (rfd[1] >= 0) close (rfd[0]);
  }
  if (g->app.pid > 0) kill (g->app.pid, 9);
  if (g->app.recoverypid > 0) kill (g->app.recoverypid, 9);
  if (g->app.pid > 0) waitpid (g->app.pid, NULL, 0);
  if (g->app.recoverypid > 0) waitpid (g->app.recoverypid, NULL, 0);
  if (g->fd[0] >= 0) close (g->fd[0]);
  if (g->fd[1] >= 0) close (g->fd[1]);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->app.pid = 0;
  g->app.recoverypid = 0;
  memset (&g->launch_t, 0, sizeof g->launch_t);

 cleanup0:
  if (g->sock >= 0) {
    close (g->sock);
    g->sock = -1;
  }
  g->state = CONFIG;
  return -1;
}

/* Calculate the appliance device name.
 *
 * The easy thing would be to use g->nr_drives (indeed, that's what we
 * used to do).  However this breaks if some of the drives being added
 * use the deprecated 'iface' parameter.  To further add confusion,
 * the format of the 'iface' parameter has never been defined, but
 * given existing usage we can assume it has one of only three values:
 * NULL, "ide" or "virtio" (which means virtio-blk).  See RHBZ#975797.
 */
static char *
make_appliance_dev (guestfs_h *g, int virtio_scsi)
{
  size_t i, index = 0;
  struct drive *drv;
  char dev[64] = "/dev/Xd";

  /* Calculate the index of the drive. */
  ITER_DRIVES (g, i, drv) {
    if (virtio_scsi) {
      if (drv->iface == NULL || STREQ (drv->iface, "ide"))
        index++;
    }
    else /* virtio-blk */ {
      if (drv->iface == NULL || STRNEQ (drv->iface, "virtio"))
        index++;
    }
  }

  dev[5] = virtio_scsi ? 's' : 'v';
  guestfs___drive_name (index, &dev[7]);

  return safe_strdup (g, dev);  /* Caller frees. */
}

/* This is called from the forked subprocess just before qemu runs, so
 * it can just print the message straight to stderr, where it will be
 * picked up and funnelled through the usual appliance event API.
 */
static void
print_qemu_command_line (guestfs_h *g, char **argv)
{
  int i = 0;
  int needs_quote;

  struct timeval tv;
  gettimeofday (&tv, NULL);
  fprintf (stderr, "[%05" PRIi64 "ms] ",
           guestfs___timeval_diff (&g->launch_t, &tv));

  while (argv[i]) {
    if (argv[i][0] == '-') /* -option starts a new line */
      fprintf (stderr, " \\\n   ");

    if (i > 0) fputc (' ', stderr);

    /* Does it need shell quoting?  This only deals with simple cases. */
    needs_quote = strcspn (argv[i], " ") != strlen (argv[i]);

    if (needs_quote) fputc ('\'', stderr);
    fprintf (stderr, "%s", argv[i]);
    if (needs_quote) fputc ('\'', stderr);
    i++;
  }
}

static void parse_qemu_version (guestfs_h *g);
static void read_all (guestfs_h *g, void *retv, const char *buf, size_t len);

/* Test qemu binary (or wrapper) runs, and do 'qemu -help' and
 * 'qemu -version' so we know what options this qemu supports and
 * the version.
 */
static int
test_qemu (guestfs_h *g)
{
  CLEANUP_CMD_CLOSE struct command *cmd1 = guestfs___new_command (g);
  CLEANUP_CMD_CLOSE struct command *cmd2 = guestfs___new_command (g);
  CLEANUP_CMD_CLOSE struct command *cmd3 = guestfs___new_command (g);
  int r;

  free (g->app.qemu_help);
  g->app.qemu_help = NULL;
  free (g->app.qemu_version);
  g->app.qemu_version = NULL;
  free (g->app.qemu_devices);
  g->app.qemu_devices = NULL;

  guestfs___cmd_add_arg (cmd1, g->qemu);
  guestfs___cmd_add_arg (cmd1, "-nographic");
  guestfs___cmd_add_arg (cmd1, "-help");
  guestfs___cmd_set_stdout_callback (cmd1, read_all, &g->app.qemu_help,
                                     CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs___cmd_run (cmd1);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  guestfs___cmd_add_arg (cmd2, g->qemu);
  guestfs___cmd_add_arg (cmd2, "-nographic");
  guestfs___cmd_add_arg (cmd2, "-version");
  guestfs___cmd_set_stdout_callback (cmd2, read_all, &g->app.qemu_version,
                                     CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs___cmd_run (cmd2);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  parse_qemu_version (g);

  guestfs___cmd_add_arg (cmd3, g->qemu);
  guestfs___cmd_add_arg (cmd3, "-nographic");
  guestfs___cmd_add_arg (cmd3, "-machine");
  guestfs___cmd_add_arg (cmd3, "accel=kvm:tcg");
  guestfs___cmd_add_arg (cmd3, "-device");
  guestfs___cmd_add_arg (cmd3, "?");
  guestfs___cmd_clear_capture_errors (cmd3);
  guestfs___cmd_set_stderr_to_stdout (cmd3);
  guestfs___cmd_set_stdout_callback (cmd3, read_all, &g->app.qemu_devices,
                                     CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs___cmd_run (cmd3);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  return 0;

 error:
  if (r == -1)
    return -1;

  guestfs___external_command_failed (g, r, g->qemu, NULL);
  return -1;
}

/* Parse g->app.qemu_version (if not NULL) into the major and minor
 * version of qemu, but don't fail if parsing is not possible.
 */
static void
parse_qemu_version (guestfs_h *g)
{
  CLEANUP_FREE char *major_s = NULL, *minor_s = NULL;
  int major_i, minor_i;

  g->app.qemu_version_major = 0;
  g->app.qemu_version_minor = 0;

  if (!g->app.qemu_version)
    return;

  if (!match2 (g, g->app.qemu_version, re_major_minor, &major_s, &minor_s)) {
  parse_failed:
    debug (g, "%s: failed to parse qemu version string '%s'",
           __func__, g->app.qemu_version);
    return;
  }

  major_i = guestfs___parse_unsigned_int (g, major_s);
  if (major_i == -1)
    goto parse_failed;

  minor_i = guestfs___parse_unsigned_int (g, minor_s);
  if (minor_i == -1)
    goto parse_failed;

  g->app.qemu_version_major = major_i;
  g->app.qemu_version_minor = minor_i;

  debug (g, "qemu version %d.%d", major_i, minor_i);
}

static void
read_all (guestfs_h *g, void *retv, const char *buf, size_t len)
{
  char **ret = retv;

  *ret = safe_strndup (g, buf, len);
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
  if (!g->app.qemu_help) {
    if (test_qemu (g) == -1)
      return -1;
  }

  if (option == NULL)
    return 1;

  return strstr (g->app.qemu_help, option) != NULL;
}

/* Test if device is supported by qemu (currently just greps the -device ?
 * output).
 */
static int
qemu_supports_device (guestfs_h *g, const char *device_name)
{
  if (!g->app.qemu_devices) {
    if (test_qemu (g) == -1)
      return -1;
  }

  return strstr (g->app.qemu_devices, device_name) != NULL;
}

/* Check if a file can be opened. */
static int
is_openable (guestfs_h *g, const char *path, int flags)
{
  int fd = open (path, flags);
  if (fd == -1) {
    debug (g, "is_openable: %s: %m", path);
    return 0;
  }
  close (fd);
  return 1;
}

static int
old_or_broken_virtio_scsi (guestfs_h *g)
{
  /* qemu 1.1 claims to support virtio-scsi but in reality it's broken. */
  if (g->app.qemu_version_major == 1 && g->app.qemu_version_minor < 2)
    return 1;

  return 0;
}

/* Returns 1 = use virtio-scsi, or 0 = use virtio-blk. */
static int
qemu_supports_virtio_scsi (guestfs_h *g)
{
  int r;

  if (!g->app.qemu_help) {
    if (test_qemu (g) == -1)
      return 0;                 /* safe option? */
  }

  /* g->app.virtio_scsi has these values:
   *   0 = untested (after handle creation)
   *   1 = supported
   *   2 = not supported (use virtio-blk)
   *   3 = test failed (use virtio-blk)
   */
  if (g->app.virtio_scsi == 0) {
    if (old_or_broken_virtio_scsi (g))
      g->app.virtio_scsi = 2;
    else {
      r = qemu_supports_device (g, "virtio-scsi-pci");
      if (r > 0)
        g->app.virtio_scsi = 1;
      else if (r == 0)
        g->app.virtio_scsi = 2;
      else
        g->app.virtio_scsi = 3;
    }
  }

  return g->app.virtio_scsi == 1;
}

static char *
qemu_drive_param (guestfs_h *g, const struct drive *drv, size_t index)
{
  size_t i;
  size_t len = 128;
  const char *p;
  char *r;
  const char *iface;

  len += strlen (drv->path) * 2; /* every "," could become ",," */
  if (drv->iface)
    len += strlen (drv->iface);
  if (drv->format)
    len += strlen (drv->format);
  if (drv->disk_label)
    len += strlen (drv->disk_label);

  r = safe_malloc (g, len);

  strcpy (r, "file=");
  i = 5;

  /* Copy the path in, escaping any "," as ",,". */
  for (p = drv->path; *p; p++) {
    if (*p == ',') {
      r[i++] = ',';
      r[i++] = ',';
    } else
      r[i++] = *p;
  }

  if (drv->iface)
    iface = drv->iface;
  else if (qemu_supports_virtio_scsi (g))
    iface = "none"; /* sic */
  else
    iface = "virtio";

  snprintf (&r[i], len-i, "%s%s%s%s%s%s,id=hd%zu,if=%s",
            drv->readonly ? ",snapshot=on" : "",
            drv->use_cache_none ? ",cache=none" : "",
            drv->format ? ",format=" : "",
            drv->format ? drv->format : "",
            drv->disk_label ? ",serial=" : "",
            drv->disk_label ? drv->disk_label : "",
            index,
            iface);

  return r;                     /* caller frees */
}

/* https://rwmj.wordpress.com/2011/01/09/how-are-linux-drives-named-beyond-drive-26-devsdz/ */
char *
guestfs___drive_name (size_t index, char *ret)
{
  if (index >= 26)
    ret = guestfs___drive_name (index/26 - 1, ret);
  index %= 26;
  *ret++ = 'a' + index;
  *ret = '\0';
  return ret;
}

static int
shutdown_appliance (guestfs_h *g, int check_for_errors)
{
  int ret = 0;
  int status;

  /* Signal qemu to shutdown cleanly, and kill the recovery process. */
  if (g->app.pid > 0) {
    debug (g, "sending SIGTERM to process %d", g->app.pid);
    kill (g->app.pid, SIGTERM);
  }
  if (g->app.recoverypid > 0) kill (g->app.recoverypid, 9);

  /* Wait for subprocess(es) to exit. */
  if (g->app.pid > 0) {
    if (waitpid (g->app.pid, &status, 0) == -1) {
      perrorf (g, "waitpid (qemu)");
      ret = -1;
    }
    else if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      guestfs___external_command_failed (g, status, g->qemu, NULL);
      ret = -1;
    }
  }
  if (g->app.recoverypid > 0) waitpid (g->app.recoverypid, NULL, 0);

  g->app.pid = g->app.recoverypid = 0;

  free (g->app.qemu_help);
  g->app.qemu_help = NULL;
  free (g->app.qemu_version);
  g->app.qemu_version = NULL;
  free (g->app.qemu_devices);
  g->app.qemu_devices = NULL;

  return ret;
}

static int
get_pid_appliance (guestfs_h *g)
{
  if (g->app.pid > 0)
    return g->app.pid;
  else {
    error (g, "get_pid: no qemu subprocess");
    return -1;
  }
}

/* Maximum number of disks. */
static int
max_disks_appliance (guestfs_h *g)
{
  if (qemu_supports_virtio_scsi (g))
    return 255;
  else
    return 27;                  /* conservative estimate */
}

struct attach_ops attach_ops_appliance = {
  .launch = launch_appliance,
  .shutdown = shutdown_appliance,
  .get_pid = get_pid_appliance,
  .max_disks = max_disks_appliance,
};
