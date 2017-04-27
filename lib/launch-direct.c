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
#include "qemuopts.h"

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

/* Some macros which make using qemuopts a bit easier. */
#define flag(flag)                                                      \
  do {                                                                  \
    if (qemuopts_add_flag (qopts, (flag)) == -1) goto qemuopts_error;   \
  } while (0)
#define arg(flag, value)                                                \
  do {                                                                  \
    if (qemuopts_add_arg (qopts, (flag), (value)) == -1) goto qemuopts_error; \
  } while (0)
#define arg_format(flag, fs, ...)                                       \
  do {                                                                  \
    if (qemuopts_add_arg_format (qopts, (flag), (fs), ##__VA_ARGS__) == -1) \
      goto qemuopts_error;                                              \
  } while (0)
#define arg_noquote(flag, value)                                        \
  do {                                                                  \
    if (qemuopts_add_arg_noquote (qopts, (flag), (value)) == -1)        \
      goto qemuopts_error;                                              \
  } while (0)
#define start_list(flag)                                                \
  if (qemuopts_start_arg_list (qopts, (flag)) == -1) goto qemuopts_error; \
  do
#define append_list(value)                                       \
  do {                                                           \
    if (qemuopts_append_arg_list (qopts, (value)) == -1)         \
      goto qemuopts_error;                                       \
  } while (0)
#define append_list_format(fs, ...)                                     \
  do {                                                                  \
    if (qemuopts_append_arg_list_format (qopts, (fs), ##__VA_ARGS__) == -1) \
      goto qemuopts_error;                                              \
  } while (0)
#define end_list()                                                      \
  while (0);                                                            \
  do {                                                                  \
    if (qemuopts_end_arg_list (qopts) == -1) goto qemuopts_error;       \
  } while (0)

/**
 * Add the standard elements of the C<-drive> parameter.
 */
static int
add_drive_standard_params (guestfs_h *g, struct backend_direct_data *data,
                           struct qemuopts *qopts,
                           size_t i, struct drive *drv)
{
  if (!drv->overlay) {
    CLEANUP_FREE char *file = NULL;

    /* file= parameter. */
    file = guestfs_int_drive_source_qemu_param (g, &drv->src);
    append_list_format ("file=%s", file);

    if (drv->readonly)
      append_list ("snapshot=on");
    append_list_format ("cache=%s",
                        drv->cachemode ? drv->cachemode : "writeback");
    if (drv->src.format)
      append_list_format ("format=%s", drv->src.format);
    if (drv->disk_label)
      append_list_format ("serial=%s", drv->disk_label);
    if (drv->copyonread)
      append_list ("copy-on-read=on");

    /* Discard mode. */
    switch (drv->discard) {
    case discard_disable:
      /* Since the default is always discard=ignore, don't specify it
       * on the command line.  This also avoids unnecessary breakage
       * with qemu < 1.5 which didn't have the option at all.
       */
      break;
    case discard_enable:
      if (!guestfs_int_discard_possible (g, drv, &data->qemu_version))
        return -1;
      /*FALLTHROUGH*/
    case discard_besteffort:
      /* I believe from reading the code that this is always safe as
       * long as qemu >= 1.5.
       */
      if (guestfs_int_version_ge (&data->qemu_version, 1, 5, 0))
        append_list ("discard=unmap");
      break;
    }
  }
  else {
    /* Writable qcow2 overlay on top of read-only drive. */
    append_list_format ("file=%s", drv->overlay);
    append_list ("cache=unsafe");
    append_list ("format=qcow2");
    if (drv->disk_label)
      append_list_format ("serial=%s", drv->disk_label);
  }

  append_list_format ("id=hd%zu", i);

  return 0;

  /* This label is called implicitly from the qemuopts macros on error. */
 qemuopts_error:
  perrorf (g, "qemuopts");
  return -1;
}

static int
add_drive (guestfs_h *g, struct backend_direct_data *data,
           struct qemuopts *qopts, size_t i, struct drive *drv)
{
  /* If there's an explicit 'iface', use it.  Otherwise default to
   * virtio-scsi.
   */
  if (drv->iface && STREQ (drv->iface, "virtio")) { /* virtio-blk */
    start_list ("-drive") {
      if (add_drive_standard_params (g, data, qopts, i, drv) == -1)
        return -1;
      append_list ("if=none");
    } end_list ();
    start_list ("-device") {
      append_list (VIRTIO_BLK);
      append_list_format ("drive=hd%zu", i);
    } end_list ();
  }
#if defined(__arm__) || defined(__aarch64__) || defined(__powerpc__)
  else if (drv->iface && STREQ (drv->iface, "ide")) {
    error (g, "'ide' interface does not work on ARM or PowerPC");
    return -1;
  }
#endif
  else if (drv->iface) {
    start_list ("-drive") {
      if (add_drive_standard_params (g, data, qopts, i, drv) == -1)
        return -1;
      append_list_format ("if=%s", drv->iface);
    } end_list ();
  }
  else /* default case: virtio-scsi */ {
    start_list ("-drive") {
      if (add_drive_standard_params (g, data, qopts, i, drv) == -1)
        return -1;
      append_list ("if=none");
    } end_list ();
    start_list ("-device") {
      append_list ("scsi-hd");
      append_list_format ("drive=hd%zu", i);
    } end_list ();
  }

  return 0;

  /* This label is called implicitly from the qemuopts macros on error. */
 qemuopts_error:
  perrorf (g, "qemuopts");
  return -1;
}

static int
add_drives (guestfs_h *g, struct backend_direct_data *data,
            struct qemuopts *qopts)
{
  size_t i;
  struct drive *drv;

  ITER_DRIVES (g, i, drv) {
    if (add_drive (g, data, qopts, i, drv) == -1)
      return -1;
  }

  return 0;
}

static int
launch_direct (guestfs_h *g, void *datav, const char *arg)
{
  struct backend_direct_data *data = datav;
  struct qemuopts *qopts = NULL;
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
  struct hv_param *hp;
  bool has_kvm;
  int force_tcg;
  const char *cpu_model;
  CLEANUP_FREE char *append = NULL;
  CLEANUP_FREE_STRING_LIST char **argv = NULL;

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
  qopts = qemuopts_create ();
  if (qopts == NULL) {
  qemuopts_error:
    perrorf (g, "qemuopts");
    goto cleanup0;
  }
  if (qemuopts_set_binary (qopts, g->hv) == -1) goto qemuopts_error;

  /* CVE-2011-4127 mitigation: Disable SCSI ioctls on virtio-blk
   * devices.
   */
  arg ("-global", VIRTIO_BLK ".scsi=off");

  if (guestfs_int_qemu_supports (g, data->qemu_data, "-nodefconfig"))
    flag ("-nodefconfig");

  /* This oddly named option doesn't actually enable FIPS.  It just
   * causes qemu to do the right thing if FIPS is enabled in the
   * kernel.  So like libvirt, we pass it unconditionally.
   */
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-enable-fips"))
    flag ("-enable-fips");

  /* Newer versions of qemu (from around 2009/12) changed the
   * behaviour of monitors so that an implicit '-monitor stdio' is
   * assumed if we are in -nographic mode and there is no other
   * -monitor option.  Only a single stdio device is allowed, so
   * this broke the '-serial stdio' option.  There is a new flag
   * called -nodefaults which gets rid of all this default crud, so
   * let's use that to avoid this and any future surprises.
   */
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-nodefaults"))
    flag ("-nodefaults");

  /* This disables the host-side display (SDL, Gtk). */
  arg ("-display", "none");

  /* See guestfs.pod / gdb */
  if (guestfs_int_get_backend_setting_bool (g, "gdb") > 0) {
    flag ("-S");
    flag ("-s");
    warning (g, "qemu debugging is enabled, connect gdb to tcp::1234 to begin");
  }

  start_list ("-machine") {
#ifdef MACHINE_TYPE
    append_list (MACHINE_TYPE);
#endif
#ifdef __aarch64__
    if (has_kvm && !force_tcg)
      append_list ("gic-version=host");
#endif
    append_list_format ("accel=%s", !force_tcg ? "kvm:tcg" : "tcg");
  } end_list ();

  cpu_model = guestfs_int_get_cpu_model (has_kvm && !force_tcg);
  if (cpu_model)
    arg ("-cpu", cpu_model);

  if (g->smp > 1)
    arg_format ("-smp", "%d", g->smp);

  arg_format ("-m", "%d", g->memsize);

  /* Force exit instead of reboot on panic */
  flag ("-no-reboot");

  /* These are recommended settings, see RHBZ#1053847. */
  arg ("-rtc", "driftfix=slew");
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-no-hpet"))
    flag ("-no-hpet");
  if (guestfs_int_version_ge (&data->qemu_version, 1, 3, 0))
    arg ("-global", "kvm-pit.lost_tick_policy=discard");

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
    start_list ("-drive") {
      append_list ("if=pflash");
      append_list ("format=raw");
      append_list_format ("file=%s", uefi_code);
      append_list ("readonly");
    } end_list ();
    if (uefi_vars) {
      start_list ("-drive") {
        append_list ("if=pflash");
        append_list ("format=raw");
        append_list_format ("file=%s", uefi_vars);
      } end_list ();
    }
  }

  /* Kernel and initrd. */
  arg ("-kernel", kernel);
  arg ("-initrd", initrd);

  /* Add a random number generator (backend for virtio-rng).  This
   * isn't strictly necessary but means we won't need to hang around
   * when needing entropy.
   */
  if (guestfs_int_qemu_supports_device (g, data->qemu_data,
                                        "virtio-rng-pci")) {
    start_list ("-object") {
      append_list ("rng-random");
      append_list ("filename=/dev/urandom");
      append_list ("id=rng0");
    } end_list ();
    start_list ("-device") {
      append_list ("virtio-rng-pci");
      append_list ("rng=rng0");
    } end_list ();
  }

  /* Create the virtio-scsi bus. */
  start_list ("-device") {
    append_list (VIRTIO_SCSI);
    append_list ("id=scsi");
  } end_list ();

  /* Add drives (except for the appliance drive). */
  if (add_drives (g, data, qopts) == -1)
    goto cleanup0;

  /* Add the ext2 appliance drive (after all the drives). */
  if (has_appliance_drive) {
    start_list ("-drive") {
      append_list_format ("file=%s", appliance);
      append_list ("snapshot=on");
      append_list ("id=appliance");
      append_list ("cache=unsafe");
      append_list ("if=none");
      append_list ("format=raw");
    } end_list ();
    start_list ("-device") {
      append_list ("scsi-hd");
      append_list ("drive=appliance");
    } end_list ();

    appliance_dev = make_appliance_dev (g);
  }

  /* Create the virtio serial bus. */
  arg ("-device", VIRTIO_SERIAL);

  /* Create the serial console. */
  arg ("-serial", "stdio");

  if (g->verbose &&
      guestfs_int_qemu_supports_device (g, data->qemu_data,
                                        "Serial Graphics Adapter")) {
    /* Use sgabios instead of vgabios.  This means we'll see BIOS
     * messages on the serial port, and also works around this bug
     * in qemu 1.1.0:
     * https://bugs.launchpad.net/qemu/+bug/1021649
     * QEmu has included sgabios upstream since just before 1.0.
     */
    arg ("-device", "sga");
  }

  /* Set up virtio-serial for the communications channel. */
  start_list ("-chardev") {
    append_list ("socket");
    append_list_format ("path=%s", data->guestfsd_sock);
    append_list ("id=channel0");
  } end_list ();
  start_list ("-device") {
    append_list ("virtserialport");
    append_list ("chardev=channel0");
    append_list ("name=org.libguestfs.channel.0");
  } end_list ();

  /* Enable user networking. */
  if (g->enable_network) {
    start_list ("-netdev") {
      append_list ("user");
      append_list ("id=usernet");
      append_list ("net=169.254.0.0/16");
    } end_list ();
    start_list ("-device") {
      append_list (VIRTIO_NET);
      append_list ("netdev=usernet");
    } end_list ();
  }

  flags = 0;
  if (!has_kvm || force_tcg)
    flags |= APPLIANCE_COMMAND_LINE_IS_TCG;
  append = guestfs_int_appliance_command_line (g, appliance_dev, flags);
  arg ("-append", append);

  /* Note: custom command line parameters must come last so that
   * qemu -set parameters can modify previously added options.
   */

  /* Add any qemu parameters. */
  for (hp = g->hv_params; hp; hp = hp->next) {
    if (!hp->hv_value)
      flag (hp->hv_param);
    else
      arg_noquote (hp->hv_param, hp->hv_value);
  }

  /* Get the argv list from the command line. */
  argv = qemuopts_to_argv (qopts);

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
      qemuopts_to_channel (qopts, stderr);

    /* Put qemu in a new process group. */
    if (g->pgroup)
      setpgid (0, 0);

    setenv ("LC_ALL", "C", 1);
    setenv ("QEMU_AUDIO_DRV", "none", 1); /* Prevents qemu opening /dev/dsp */

    TRACE0 (launch_run_qemu);

    execv (g->hv, argv);        /* Run qemu. */
    perror (g->hv);
    _exit (EXIT_FAILURE);
  }

  /* Parent (library). */
  data->pid = r;

  qemuopts_free (qopts);
  qopts = NULL;

  /* Fork the recovery process off which will kill qemu if the parent
   * process fails to do so (eg. if the parent segfaults).
   */
  data->recoverypid = -1;
  if (g->recovery_proc) {
    r = fork ();
    if (r == 0) {
      size_t i;
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
  if (qopts != NULL)
    qemuopts_free (qopts);
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
