/* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int is_openable (guestfs_h *g, const char *path, int flags);
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

    if (quote == ' ')
      nextp = endp+1;
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

  /* At present you must add drives before starting the appliance.  In
   * future when we enable hotplugging you won't need to do this.
   */
  if (!g->drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  guestfs___launch_send_progress (g, 0);

  TRACE0 (launch_build_appliance_start);

  /* Locate and/or build the appliance. */
  char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  if (guestfs___build_appliance (g, &kernel, &initrd, &appliance) == -1)
    return -1;

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

    /* Add any qemu parameters. */
    for (qp = g->qemu_params; qp; qp = qp->next) {
      add_cmdline (g, qp->qemu_param);
      if (qp->qemu_value)
        add_cmdline (g, qp->qemu_value);
    }

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
    struct drive *drv = g->drives;
    size_t drv_index = 0;

    if (virtio_scsi) {
      /* Create the virtio-scsi bus. */
      add_cmdline (g, "-device");
      add_cmdline (g, "virtio-scsi-pci,id=scsi");
    }

    while (drv != NULL) {
      /* Construct the final -drive parameter. */
      char *buf = qemu_drive_param (g, drv, drv_index);

      add_cmdline (g, "-drive");
      add_cmdline (g, buf);
      free (buf);

      if (virtio_scsi && drv->iface == NULL) {
        char buf2[64];
        snprintf (buf2, sizeof buf2, "scsi-hd,drive=hd%zu", drv_index);
        add_cmdline (g, "-device");
        add_cmdline (g, buf2);
      }

      drv = drv->next;
      drv_index++;
    }

    char appliance_root[64] = "";

    /* Add the ext2 appliance drive (after all the drives). */
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
      snprintf (buf2, sizeof buf2, "file=%s,snapshot=on,id=appliance,if=%s%s",
                appliance, virtio_scsi ? "none" : "virtio", cachemode);
      add_cmdline (g, buf2);

      if (virtio_scsi) {
        add_cmdline (g, "-device");
        add_cmdline (g, "scsi-hd,drive=appliance");
      }

      snprintf (appliance_root, sizeof appliance_root, "root=/dev/%cd",
                virtio_scsi ? 's' : 'v');
      guestfs___drive_name (drv_index, &appliance_root[12]);
    }

    if (STRNEQ (QEMU_OPTIONS, "")) {
      /* Add the extra options for the qemu command line specified
       * at configure time.
       */
      add_cmdline_shell_unquoted (g, QEMU_OPTIONS);
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

    /* Use sgabios instead of vgabios.  This means we'll see BIOS
     * messages on the serial port, and also works around this bug
     * in qemu 1.1.0:
     * https://bugs.launchpad.net/qemu/+bug/1021649
     * QEmu has included sgabios upstream since just before 1.0.
     */
    add_cmdline (g, "-device");
    add_cmdline (g, "sga");

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

#if defined(__arm__)
#define SERIAL_CONSOLE "ttyAMA0"
#else
#define SERIAL_CONSOLE "ttyS0"
#endif

#define LINUX_CMDLINE							\
    "panic=1 "         /* force kernel to panic if daemon exits */	\
    "console=" SERIAL_CONSOLE " " /* serial console */		        \
    "udevtimeout=600 " /* good for very slow systems (RHBZ#480319) */	\
    "no_timer_check "  /* fix for RHBZ#502058 */                        \
    "acpi=off "        /* we don't need ACPI, turn it off */		\
    "printk.time=1 "   /* display timestamp before kernel messages */   \
    "cgroup_disable=memory " /* saves us about 5 MB of RAM */

    /* Linux kernel command line. */
    snprintf (buf, sizeof buf,
              LINUX_CMDLINE
              "%s "             /* (root) */
              "%s "             /* (selinux) */
              "%s "             /* (verbose) */
              "TERM=%s "        /* (TERM environment variable) */
              "%s",             /* (append) */
              appliance_root,
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

  free (kernel);
  kernel = NULL;
  free (initrd);
  initrd = NULL;
  free (appliance);
  appliance = NULL;

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
  } else {
    g->fd[0] = open ("/dev/null", O_RDWR|O_CLOEXEC);
    if (g->fd[0] == -1) {
      perrorf (g, "open /dev/null");
      goto cleanup1;
    }
    g->fd[1] = dup (g->fd[0]);
    if (g->fd[1] == -1) {
      perrorf (g, "dup");
      close (g->fd[0]);
      g->fd[0] = -1;
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

  uint32_t size;
  void *buf = NULL;
  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) {
    error (g, _("guestfs_launch failed, see earlier error messages"));
    goto cleanup1;
  }

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

  TRACE0 (launch_end);

  guestfs___launch_send_progress (g, 12);

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
  free (kernel);
  free (initrd);
  free (appliance);
  return -1;
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

static int test_qemu_cmd (guestfs_h *g, const char *cmd, char **ret);
static int read_all (guestfs_h *g, FILE *fp, char **ret);

/* Test qemu binary (or wrapper) runs, and do 'qemu -help' and
 * 'qemu -version' so we know what options this qemu supports and
 * the version.
 */
static int
test_qemu (guestfs_h *g)
{
  char cmd[1024];

  free (g->app.qemu_help);
  g->app.qemu_help = NULL;
  free (g->app.qemu_version);
  g->app.qemu_version = NULL;
  free (g->app.qemu_devices);
  g->app.qemu_devices = NULL;

  snprintf (cmd, sizeof cmd, "LC_ALL=C '%s' -nographic -help", g->qemu);

  /* If this command doesn't work then it probably indicates that the
   * qemu binary is missing.
   */
  if (test_qemu_cmd (g, cmd, &g->app.qemu_help) == -1) {
  qemu_error:
    error (g, _("command failed: %s\nerrno: %s\n\nIf qemu is located on a non-standard path, try setting the LIBGUESTFS_QEMU\nenvironment variable.  There may also be errors printed above."),
           cmd, strerror (errno));
    return -1;
  }

  snprintf (cmd, sizeof cmd, "LC_ALL=C '%s' -nographic -version 2>/dev/null",
            g->qemu);

  if (test_qemu_cmd (g, cmd, &g->app.qemu_version) == -1)
    goto qemu_error;

  snprintf (cmd, sizeof cmd,
            "LC_ALL=C '%s' -nographic -machine accel=kvm:tcg -device '?' 2>&1",
            g->qemu);

  if (test_qemu_cmd (g, cmd, &g->app.qemu_devices) == -1)
    goto qemu_error;

  return 0;
}

static int
test_qemu_cmd (guestfs_h *g, const char *cmd, char **ret)
{
  FILE *fp;

  fp = popen (cmd, "r");
  if (fp == NULL)
    return -1;

  if (read_all (g, fp, ret) == -1) {
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0)
    return -1;

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
  if (ferror (fp))
    return -1;
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

/* Returns 1 = use virtio-scsi, or 0 = use virtio-blk. */
static int
qemu_supports_virtio_scsi (guestfs_h *g)
{
  int r;

  /* g->app.virtio_scsi has these values:
   *   0 = untested (after handle creation)
   *   1 = supported
   *   2 = not supported (use virtio-blk)
   *   3 = test failed (use virtio-blk)
   */
  if (g->app.virtio_scsi == 0) {
    r = qemu_supports_device (g, "virtio-scsi-pci");
    if (r > 0)
      g->app.virtio_scsi = 1;
    else if (r == 0)
      g->app.virtio_scsi = 2;
    else
      g->app.virtio_scsi = 3;
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

  snprintf (&r[i], len-i, "%s%s%s%s,id=hd%zu,if=%s",
            drv->readonly ? ",snapshot=on" : "",
            drv->use_cache_none ? ",cache=none" : "",
            drv->format ? ",format=" : "",
            drv->format ? drv->format : "",
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
shutdown_appliance (guestfs_h *g)
{
  int ret = 0;
  int status, sig;

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
    else if (WIFEXITED (status) && WEXITSTATUS (status) != 0) {
      error (g, "qemu failed (status %d)", WEXITSTATUS (status));
      ret = -1;
    }
    else if (WIFSIGNALED (status)) {
      sig = WTERMSIG (status);
      error (g, "qemu terminated by signal %d (%s)", sig, strsignal (sig));
      ret = -1;
    }
    else if (WIFSTOPPED (status)) {
      sig = WSTOPSIG (status);
      error (g, "qemu stopped by signal %d (%s)", sig, strsignal (sig));
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
