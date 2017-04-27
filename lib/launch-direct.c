/* libguestfs
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * Implementation of the C<direct> backend.
 *
 * For more details see L<guestfs(3)/BACKENDS>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <assert.h>
#include <string.h>
#include <libintl.h>

#include "cloexec.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

/* Per-handle data. */
struct backend_direct_data {
  pid_t pid;                    /* Qemu PID. */
  pid_t recoverypid;            /* Recovery process PID. */

  struct version qemu_version;  /* qemu version (0 if unable to parse). */
  struct qemu_data *qemu_data;  /* qemu -help output etc. */

  char guestfsd_sock[UNIX_PATH_MAX]; /* Path to daemon socket. */
};

static int is_openable (guestfs_h *g, const char *path, int flags);
static char *make_appliance_dev (guestfs_h *g);
static void print_qemu_command_line (guestfs_h *g, char **argv);

static char *
create_cow_overlay_direct (guestfs_h *g, void *datav, struct drive *drv)
{
  char *overlay;
  CLEANUP_FREE char *backing_drive = NULL;
  struct guestfs_disk_create_argv optargs;

  backing_drive = guestfs_int_drive_source_qemu_param (g, &drv->src);
  if (!backing_drive)
    return NULL;

  if (guestfs_int_lazy_make_tmpdir (g) == -1)
    return NULL;

  overlay = safe_asprintf (g, "%s/overlay%d", g->tmpdir, ++g->unique);

  optargs.bitmask = GUESTFS_DISK_CREATE_BACKINGFILE_BITMASK;
  optargs.backingfile = backing_drive;
  if (drv->src.format) {
    optargs.bitmask |= GUESTFS_DISK_CREATE_BACKINGFORMAT_BITMASK;
    optargs.backingformat = drv->src.format;
  }

  if (guestfs_disk_create_argv (g, overlay, "qcow2", -1, &optargs) == -1) {
    free (overlay);
    return NULL;
  }

  /* Caller sets g->overlay in the handle to this, and then manages
   * the memory.
   */
  return overlay;
}

/* On Debian, /dev/kvm is mode 0660 and group kvm, so users need to
 * add themselves to the kvm group otherwise things are going to be
 * very slow (this is Debian bug 640328).  Warn about this.
 */
static void
debian_kvm_warning (guestfs_h *g)
{
#ifdef __linux__
  uid_t euid = geteuid ();
  gid_t egid = getegid ();
  struct stat statbuf;
  gid_t kvm_group;
  CLEANUP_FREE gid_t *groups = NULL;
  int ngroups;
  size_t i;

  /* Doesn't apply if running as root. */
  if (euid == 0)
    return;

  if (stat ("/dev/kvm", &statbuf) == -1)
    return;
  if ((statbuf.st_mode & 0777) != 0660)
    return;

  /* They might be running libguestfs as root or have chowned /dev/kvm, so: */
  if (geteuid () == statbuf.st_uid)
    return;

  kvm_group = statbuf.st_gid;

  /* Is the current process a member of the KVM group? */
  if (egid == kvm_group)
    return;

  ngroups = getgroups (0, NULL);
  if (ngroups > 0) {
    groups = safe_malloc (g, ngroups * sizeof (gid_t));
    if (getgroups (ngroups, groups) == -1) {
      warning (g, "getgroups: %m (ignored)");
      return;
    }
    for (i = 0; i < (size_t) ngroups; ++i) {
      if (groups[i] == kvm_group)
        return;
    }
  }

  /* No, so emit the warning.  Note that \n characters cannot appear
   * in warnings.
   */
  warning (g,
	   _("current user is not a member of the KVM group (group ID %d). "
	     "This user cannot access /dev/kvm, so libguestfs may run very slowly. "
	     "It is recommended that you 'chmod 0666 /dev/kvm' or add the current user "
	     "to the KVM group (you might need to log out and log in again)."),
           (int) kvm_group);
#endif /* __linux__ */
}

static int
launch_direct (guestfs_h *g, void *datav, const char *arg)
{
  struct backend_direct_data *data = datav;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (cmdline);
  int daemon_accept_sock = -1, console_sock = -1;
  int r;
  int flags;
  int sv[2];
  struct sockaddr_un addr;
  CLEANUP_FREE char *uefi_code = NULL, *uefi_vars = NULL;
  int uefi_flags;
  CLEANUP_FREE char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  int has_appliance_drive;
  CLEANUP_FREE char *appliance_dev = NULL;
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;
  struct drive *drv;
  size_t i;
  struct hv_param *hp;
  bool has_kvm;
  int force_tcg;
  const char *cpu_model;

  /* At present you must add drives before starting the appliance.  In
   * future when we enable hotplugging you won't need to do this.
   */
  if (!g->nr_drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  /* Try to guess if KVM is available.  We are just checking that
   * /dev/kvm is openable.  That's not reliable, since /dev/kvm
   * might be openable by qemu but not by us (think: SELinux) in
   * which case the user would not get hardware virtualization,
   * although at least shouldn't fail.
   */
  has_kvm = is_openable (g, "/dev/kvm", O_RDWR|O_CLOEXEC);

  force_tcg = guestfs_int_get_backend_setting_bool (g, "force_tcg");
  if (force_tcg == -1)
    return -1;

  if (!has_kvm && !force_tcg)
    debian_kvm_warning (g);

  guestfs_int_launch_send_progress (g, 0);

  TRACE0 (launch_build_appliance_start);

  /* Locate and/or build the appliance. */
  if (guestfs_int_build_appliance (g, &kernel, &initrd, &appliance) == -1)
    return -1;
  has_appliance_drive = appliance != NULL;

  TRACE0 (launch_build_appliance_end);

  guestfs_int_launch_send_progress (g, 3);

  debug (g, "begin testing qemu features");

  /* Get qemu help text and version. */
  if (data->qemu_data == NULL) {
    data->qemu_data = guestfs_int_test_qemu (g, &data->qemu_version);
    if (data->qemu_data == NULL)
      goto cleanup0;
  }

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  if (guestfs_int_create_socketname (g, "guestfsd.sock",
                                     &data->guestfsd_sock) == -1)
    goto cleanup0;

  daemon_accept_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (daemon_accept_sock == -1) {
    perrorf (g, "socket");
    goto cleanup0;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, data->guestfsd_sock, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  if (bind (daemon_accept_sock, (struct sockaddr *) &addr,
            sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup0;
  }

  if (listen (daemon_accept_sock, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup0;
  }

  if (!g->direct_mode) {
    if (socketpair (AF_LOCAL, SOCK_STREAM|SOCK_CLOEXEC, 0, sv) == -1) {
      perrorf (g, "socketpair");
      goto cleanup0;
    }
  }

  debug (g, "finished testing qemu features");

  /* Construct the qemu command line.  We have to do this before
   * forking, because after fork we are not allowed to use
   * non-signal-safe functions such as malloc.
   */
#define ADD_CMDLINE(str)			\
  guestfs_int_add_string (g, &cmdline, (str))
#define ADD_CMDLINE_STRING_NODUP(str)			\
  guestfs_int_add_string_nodup (g, &cmdline, (str))
#define ADD_CMDLINE_PRINTF(fs,...)				\
  guestfs_int_add_sprintf (g, &cmdline, (fs), ##__VA_ARGS__)

  ADD_CMDLINE (g->hv);

  /* CVE-2011-4127 mitigation: Disable SCSI ioctls on virtio-blk
   * devices.
   */
  ADD_CMDLINE ("-global");
  ADD_CMDLINE (VIRTIO_BLK ".scsi=off");

  if (guestfs_int_qemu_supports (g, data->qemu_data, "-nodefconfig"))
    ADD_CMDLINE ("-nodefconfig");

  /* This oddly named option doesn't actually enable FIPS.  It just
   * causes qemu to do the right thing if FIPS is enabled in the
   * kernel.  So like libvirt, we pass it unconditionally.
   */
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-enable-fips"))
    ADD_CMDLINE ("-enable-fips");

  /* Newer versions of qemu (from around 2009/12) changed the
   * behaviour of monitors so that an implicit '-monitor stdio' is
   * assumed if we are in -nographic mode and there is no other
   * -monitor option.  Only a single stdio device is allowed, so
   * this broke the '-serial stdio' option.  There is a new flag
   * called -nodefaults which gets rid of all this default crud, so
   * let's use that to avoid this and any future surprises.
   */
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-nodefaults"))
    ADD_CMDLINE ("-nodefaults");

  /* This disables the host-side display (SDL, Gtk). */
  ADD_CMDLINE ("-display");
  ADD_CMDLINE ("none");

  /* See guestfs.pod / gdb */
  if (guestfs_int_get_backend_setting_bool (g, "gdb") > 0) {
    ADD_CMDLINE ("-S");
    ADD_CMDLINE ("-s");
    warning (g, "qemu debugging is enabled, connect gdb to tcp::1234 to begin");
  }

  ADD_CMDLINE ("-machine");
  ADD_CMDLINE_PRINTF (
#ifdef MACHINE_TYPE
                      MACHINE_TYPE ","
#endif
#ifdef __aarch64__
                      "%s"      /* gic-version */
#endif
                      "accel=%s",
#ifdef __aarch64__
                      has_kvm && !force_tcg ? "gic-version=host," : "",
#endif
                      !force_tcg ? "kvm:tcg" : "tcg");

  cpu_model = guestfs_int_get_cpu_model (has_kvm && !force_tcg);
  if (cpu_model) {
    ADD_CMDLINE ("-cpu");
    ADD_CMDLINE (cpu_model);
  }

  if (g->smp > 1) {
    ADD_CMDLINE ("-smp");
    ADD_CMDLINE_PRINTF ("%d", g->smp);
  }

  ADD_CMDLINE ("-m");
  ADD_CMDLINE_PRINTF ("%d", g->memsize);

  /* Force exit instead of reboot on panic */
  ADD_CMDLINE ("-no-reboot");

  /* These are recommended settings, see RHBZ#1053847. */
  ADD_CMDLINE ("-rtc");
  ADD_CMDLINE ("driftfix=slew");
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-no-hpet")) {
    ADD_CMDLINE ("-no-hpet");
  }
  if (guestfs_int_version_ge (&data->qemu_version, 1, 3, 0)) {
    ADD_CMDLINE ("-global");
    ADD_CMDLINE ("kvm-pit.lost_tick_policy=discard");
  }

  /* UEFI (firmware) if required. */
  if (guestfs_int_get_uefi (g, &uefi_code, &uefi_vars, &uefi_flags) == -1)
    goto cleanup0;
  if (uefi_flags & UEFI_FLAG_SECURE_BOOT_REQUIRED) {
    /* Implementing this requires changes to the qemu command line.
     * See RHBZ#1367615 for details.  As the guestfs_int_get_uefi
     * function is only implemented for aarch64, and UEFI secure boot
     * is some way off on aarch64 (2017/2018), we only need to worry
     * about this later.
     */
    error (g, "internal error: direct backend "
           "does not implement UEFI secure boot, "
           "see comments in the code");
    goto cleanup0;
  }
  if (uefi_code) {
    ADD_CMDLINE ("-drive");
    ADD_CMDLINE_PRINTF ("if=pflash,format=raw,file=%s,readonly", uefi_code);
    if (uefi_vars) {
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("if=pflash,format=raw,file=%s", uefi_vars);
    }
  }

  /* Kernel and initrd. */
  ADD_CMDLINE ("-kernel");
  ADD_CMDLINE (kernel);
  ADD_CMDLINE ("-initrd");
  ADD_CMDLINE (initrd);

  /* Add a random number generator (backend for virtio-rng).  This
   * isn't strictly necessary but means we won't need to hang around
   * when needing entropy.
   */
  if (guestfs_int_qemu_supports_device (g, data->qemu_data,
                                        "virtio-rng-pci")) {
    ADD_CMDLINE ("-object");
    ADD_CMDLINE ("rng-random,filename=/dev/urandom,id=rng0");
    ADD_CMDLINE ("-device");
    ADD_CMDLINE ("virtio-rng-pci,rng=rng0");
  }

  /* Create the virtio-scsi bus. */
  ADD_CMDLINE ("-device");
  ADD_CMDLINE (VIRTIO_SCSI ",id=scsi");

  /* Add drives */
  ITER_DRIVES (g, i, drv) {
    CLEANUP_FREE char *file = NULL, *escaped_file = NULL, *param = NULL;

    if (!drv->overlay) {
      const char *discard_mode = "";

      switch (drv->discard) {
      case discard_disable:
        /* Since the default is always discard=ignore, don't specify it
         * on the command line.  This also avoids unnecessary breakage
         * with qemu < 1.5 which didn't have the option at all.
         */
        break;
      case discard_enable:
        if (!guestfs_int_discard_possible (g, drv, &data->qemu_version))
          goto cleanup0;
        /*FALLTHROUGH*/
      case discard_besteffort:
        /* I believe from reading the code that this is always safe as
         * long as qemu >= 1.5.
         */
        if (guestfs_int_version_ge (&data->qemu_version, 1, 5, 0))
          discard_mode = ",discard=unmap";
        break;
      }

      /* Make the file= parameter. */
      file = guestfs_int_drive_source_qemu_param (g, &drv->src);
      escaped_file = guestfs_int_qemu_escape_param (g, file);

      /* Make the first part of the -drive parameter, everything up to
       * the if=... at the end.
       */
      param = safe_asprintf
        (g, "file=%s%s,cache=%s%s%s%s%s%s%s,id=hd%zu",
         escaped_file,
         drv->readonly ? ",snapshot=on" : "",
         drv->cachemode ? drv->cachemode : "writeback",
         discard_mode,
         drv->src.format ? ",format=" : "",
         drv->src.format ? drv->src.format : "",
         drv->disk_label ? ",serial=" : "",
         drv->disk_label ? drv->disk_label : "",
         drv->copyonread ? ",copy-on-read=on" : "",
         i);
    }
    else {
      /* Writable qcow2 overlay on top of read-only drive. */
      escaped_file = guestfs_int_qemu_escape_param (g, drv->overlay);
      param = safe_asprintf
        (g, "file=%s,cache=unsafe,format=qcow2%s%s,id=hd%zu",
         escaped_file,
         drv->disk_label ? ",serial=" : "",
         drv->disk_label ? drv->disk_label : "",
         i);
    }

    /* If there's an explicit 'iface', use it.  Otherwise default to
     * virtio-scsi.
     */
    if (drv->iface && STREQ (drv->iface, "virtio")) { /* virtio-blk */
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("%s,if=none" /* sic */, param);
      ADD_CMDLINE ("-device");
      ADD_CMDLINE_PRINTF (VIRTIO_BLK ",drive=hd%zu", i);
    }
#if defined(__arm__) || defined(__aarch64__) || defined(__powerpc__)
    else if (drv->iface && STREQ (drv->iface, "ide")) {
      error (g, "'ide' interface does not work on ARM or PowerPC");
      goto cleanup0;
    }
#endif
    else if (drv->iface) {
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("%s,if=%s", param, drv->iface);
    }
    else /* virtio-scsi */ {
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("%s,if=none" /* sic */, param);
      ADD_CMDLINE ("-device");
      ADD_CMDLINE_PRINTF ("scsi-hd,drive=hd%zu", i);
    }
  }

  /* Add the ext2 appliance drive (after all the drives). */
  if (has_appliance_drive) {
    ADD_CMDLINE ("-drive");
    ADD_CMDLINE_PRINTF ("file=%s,snapshot=on,id=appliance,"
                        "cache=unsafe,if=none,format=raw",
                        appliance);

    ADD_CMDLINE ("-device");
    ADD_CMDLINE ("scsi-hd,drive=appliance");

    appliance_dev = make_appliance_dev (g);
  }

  /* Create the virtio serial bus. */
  ADD_CMDLINE ("-device");
  ADD_CMDLINE (VIRTIO_SERIAL);

  /* Create the serial console. */
  ADD_CMDLINE ("-serial");
  ADD_CMDLINE ("stdio");

  if (g->verbose &&
      guestfs_int_qemu_supports_device (g, data->qemu_data,
                                        "Serial Graphics Adapter")) {
    /* Use sgabios instead of vgabios.  This means we'll see BIOS
     * messages on the serial port, and also works around this bug
     * in qemu 1.1.0:
     * https://bugs.launchpad.net/qemu/+bug/1021649
     * QEmu has included sgabios upstream since just before 1.0.
     */
    ADD_CMDLINE ("-device");
    ADD_CMDLINE ("sga");
  }

  /* Set up virtio-serial for the communications channel. */
  ADD_CMDLINE ("-chardev");
  ADD_CMDLINE_PRINTF ("socket,path=%s,id=channel0", data->guestfsd_sock);
  ADD_CMDLINE ("-device");
  ADD_CMDLINE ("virtserialport,chardev=channel0,name=org.libguestfs.channel.0");

  /* Enable user networking. */
  if (g->enable_network) {
    ADD_CMDLINE ("-netdev");
    ADD_CMDLINE ("user,id=usernet,net=169.254.0.0/16");
    ADD_CMDLINE ("-device");
    ADD_CMDLINE (VIRTIO_NET ",netdev=usernet");
  }

  ADD_CMDLINE ("-append");
  flags = 0;
  if (!has_kvm || force_tcg)
    flags |= APPLIANCE_COMMAND_LINE_IS_TCG;
  ADD_CMDLINE_STRING_NODUP
    (guestfs_int_appliance_command_line (g, appliance_dev, flags));

  /* Note: custom command line parameters must come last so that
   * qemu -set parameters can modify previously added options.
   */

  /* Add any qemu parameters. */
  for (hp = g->hv_params; hp; hp = hp->next) {
    ADD_CMDLINE (hp->hv_param);
    if (hp->hv_value)
      ADD_CMDLINE (hp->hv_value);
  }

  /* Finish off the command line. */
  guestfs_int_end_stringsbuf (g, &cmdline);

  r = fork ();
  if (r == -1) {
    perrorf (g, "fork");
    if (!g->direct_mode) {
      close (sv[0]);
      close (sv[1]);
    }
    goto cleanup0;
  }

  if (r == 0) {			/* Child (qemu). */
    if (!g->direct_mode) {
      /* Set up stdin, stdout, stderr. */
      close (0);
      close (1);
      close (sv[0]);

      /* We set the FD_CLOEXEC flag on the socket above, but now (in
       * the child) it's safe to unset this flag so qemu can use the
       * socket.
       */
      set_cloexec_flag (sv[1], 0);

      /* Stdin. */
      if (dup (sv[1]) == -1) {
      dup_failed:
        perror ("dup failed");
        _exit (EXIT_FAILURE);
      }
      /* Stdout. */
      if (dup (sv[1]) == -1)
        goto dup_failed;

      /* Particularly since qemu 0.15, qemu spews all sorts of debug
       * information on stderr.  It is useful to both capture this and
       * not confuse casual users, so send stderr to the pipe as well.
       */
      close (2);
      if (dup (sv[1]) == -1)
        goto dup_failed;

      close (sv[1]);

      /* Close any other file descriptors that we don't want to pass
       * to qemu.  This prevents file descriptors which didn't have
       * O_CLOEXEC set properly from leaking into the subprocess.  See
       * RHBZ#1123007.
       */
      close_file_descriptors (fd > 2);
    }

    /* Dump the command line (after setting up stderr above). */
    if (g->verbose)
      print_qemu_command_line (g, cmdline.argv);

    /* Put qemu in a new process group. */
    if (g->pgroup)
      setpgid (0, 0);

    setenv ("LC_ALL", "C", 1);
    setenv ("QEMU_AUDIO_DRV", "none", 1); /* Prevents qemu opening /dev/dsp */

    TRACE0 (launch_run_qemu);

    execv (g->hv, cmdline.argv); /* Run qemu. */
    perror (g->hv);
    _exit (EXIT_FAILURE);
  }

  /* Parent (library). */
  data->pid = r;

  /* Fork the recovery process off which will kill qemu if the parent
   * process fails to do so (eg. if the parent segfaults).
   */
  data->recoverypid = -1;
  if (g->recovery_proc) {
    r = fork ();
    if (r == 0) {
      struct sigaction sa;
      pid_t qemu_pid = data->pid;
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
      close_file_descriptors (1);

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
    data->recoverypid = r;
  }

  if (!g->direct_mode) {
    /* Close the other end of the socketpair. */
    close (sv[1]);

    console_sock = sv[0];       /* stdin of child */
    sv[0] = -1;
  }

  g->state = LAUNCHING;

  /* Wait for qemu to start and to connect back to us via
   * virtio-serial and send the GUESTFS_LAUNCH_FLAG message.
   */
  g->conn =
    guestfs_int_new_conn_socket_listening (g, daemon_accept_sock, console_sock);
  if (!g->conn)
    goto cleanup1;

  /* g->conn now owns these sockets. */
  daemon_accept_sock = console_sock = -1;

  r = g->conn->ops->accept_connection (g, g->conn);
  if (r == -1)
    goto cleanup1;
  if (r == 0) {
    guestfs_int_launch_failed_error (g);
    goto cleanup1;
  }

  /* NB: We reach here just because qemu has opened the socket.  It
   * does not mean the daemon is up until we read the
   * GUESTFS_LAUNCH_FLAG below.  Failures in qemu startup can still
   * happen even if we reach here, even early failures like not being
   * able to open a drive.
   */

  r = guestfs_int_recv_from_daemon (g, &size, &buf);

  if (r == -1) {
    guestfs_int_launch_failed_error (g);
    goto cleanup1;
  }

  if (size != GUESTFS_LAUNCH_FLAG) {
    guestfs_int_launch_failed_error (g);
    goto cleanup1;
  }

  debug (g, "appliance is up");

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

  guestfs_int_launch_send_progress (g, 12);

  if (has_appliance_drive)
    guestfs_int_add_dummy_appliance_drive (g);

  return 0;

 cleanup1:
  if (!g->direct_mode && sv[0] >= 0)
    close (sv[0]);
  if (data->pid > 0) kill (data->pid, 9);
  if (data->recoverypid > 0) kill (data->recoverypid, 9);
  if (data->pid > 0) guestfs_int_waitpid_noerror (data->pid);
  if (data->recoverypid > 0) guestfs_int_waitpid_noerror (data->recoverypid);
  data->pid = 0;
  data->recoverypid = 0;
  memset (&g->launch_t, 0, sizeof g->launch_t);
  guestfs_int_free_qemu_data (data->qemu_data);
  data->qemu_data = NULL;

 cleanup0:
  if (daemon_accept_sock >= 0)
    close (daemon_accept_sock);
  if (console_sock >= 0)
    close (console_sock);
  if (g->conn) {
    g->conn->ops->free_connection (g, g->conn);
    g->conn = NULL;
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
make_appliance_dev (guestfs_h *g)
{
  size_t i, index = 0;
  struct drive *drv;
  char dev[64] = "/dev/sd";

  /* Calculate the index of the drive. */
  ITER_DRIVES (g, i, drv) {
    if (drv->iface == NULL || STREQ (drv->iface, "ide"))
      index++;
  }

  guestfs_int_drive_name (index, &dev[7]);

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
           guestfs_int_timeval_diff (&g->launch_t, &tv));

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

  fputc ('\n', stderr);
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
shutdown_direct (guestfs_h *g, void *datav, int check_for_errors)
{
  struct backend_direct_data *data = datav;
  int ret = 0;
  int status;
  struct rusage rusage;

  /* Signal qemu to shutdown cleanly, and kill the recovery process. */
  if (data->pid > 0) {
    debug (g, "sending SIGTERM to process %d", data->pid);
    kill (data->pid, SIGTERM);
  }
  if (data->recoverypid > 0) kill (data->recoverypid, 9);

  /* Wait for subprocess(es) to exit. */
  if (g->recovery_proc /* RHBZ#998482 */ && data->pid > 0) {
    if (guestfs_int_wait4 (g, data->pid, &status, &rusage, "qemu") == -1)
      ret = -1;
    else if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      guestfs_int_external_command_failed (g, status, g->hv, NULL);
      ret = -1;
    }
    else
      /* Print the actual memory usage of qemu, useful for seeing
       * if techniques like DAX are having any effect.
       */
      debug (g, "qemu maxrss %ldK", rusage.ru_maxrss);
  }
  if (data->recoverypid > 0) guestfs_int_waitpid_noerror (data->recoverypid);

  data->pid = data->recoverypid = 0;

  if (data->guestfsd_sock[0] != '\0') {
    unlink (data->guestfsd_sock);
    data->guestfsd_sock[0] = '\0';
  }

  guestfs_int_free_qemu_data (data->qemu_data);
  data->qemu_data = NULL;

  return ret;
}

static int
get_pid_direct (guestfs_h *g, void *datav)
{
  struct backend_direct_data *data = datav;

  if (data->pid > 0)
    return data->pid;
  else {
    error (g, "get_pid: no qemu subprocess");
    return -1;
  }
}

/* Maximum number of disks. */
static int
max_disks_direct (guestfs_h *g, void *datav)
{
  return 255;
}

static struct backend_ops backend_direct_ops = {
  .data_size = sizeof (struct backend_direct_data),
  .create_cow_overlay = create_cow_overlay_direct,
  .launch = launch_direct,
  .shutdown = shutdown_direct,
  .get_pid = get_pid_direct,
  .max_disks = max_disks_direct,
};

void
guestfs_int_init_direct_backend (void)
{
  guestfs_int_register_backend ("direct", &backend_direct_ops);
}
