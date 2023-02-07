/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
  int qemu_mandatory_locking;   /* qemu >= 2.10 does mandatory locking */
  struct qemu_data *qemu_data;  /* qemu -help output etc. */

  char guestfsd_sock[UNIX_PATH_MAX]; /* Path to daemon socket. */
};

static char *
create_cow_overlay_direct (guestfs_h *g, void *datav, struct drive *drv)
{
  char *overlay;
  CLEANUP_FREE char *backing_drive = NULL;
  struct guestfs_disk_create_argv optargs;

  backing_drive = guestfs_int_drive_source_qemu_param (g, &drv->src);
  if (!backing_drive)
    return NULL;

  overlay = guestfs_int_make_temp_path (g, "overlay", "qcow2");
  if (!overlay)
    return NULL;

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
    if (data->qemu_mandatory_locking &&
	/* Add the file-specific locking option only for files, as
	 * qemu won't accept options unknown to the block driver in
	 * use.
	 */
	drv->src.protocol == drive_protocol_file) {
      append_list_format ("file.file.filename=%s", drv->overlay);
      append_list ("file.driver=qcow2");
      append_list ("file.backing.file.locking=off");
    }
    else {
      /* Ancient qemu (esp. qemu 1.5 in RHEL 7) didn't understand the
       * file.file.filename= parameter, so use the safer old-style
       * form of parameters unless we actually want to specify the
       * locking flag above.
       */
      append_list_format ("file=%s", drv->overlay);
      append_list ("format=qcow2");
    }
    append_list ("cache=unsafe");
  }

  append_list_format ("id=hd%zu", i);

  return 0;

  /* This label is called implicitly from the qemuopts macros on error. */
 qemuopts_error:
  perrorf (g, "qemuopts");
  return -1;
}

/**
 * Add the physical_block_size and logical_block_size elements of the C<-device>
 * parameter.
 */
static int
add_device_blocksize_params (guestfs_h *g, struct qemuopts *qopts,
                           struct drive *drv)
{
  if (drv->blocksize) {
    append_list_format ("physical_block_size=%d", drv->blocksize);
    append_list_format ("logical_block_size=%d", drv->blocksize);
  }

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
  start_list ("-drive") {
    if (add_drive_standard_params (g, data, qopts, i, drv) == -1)
      return -1;
    append_list ("if=none");
  } end_list ();
  start_list ("-device") {
    append_list ("scsi-hd");
    append_list_format ("drive=hd%zu", i);
    if (drv->disk_label)
      append_list_format ("serial=%s", drv->disk_label);
    if (add_device_blocksize_params (g, qopts, drv) == -1)
      return -1;
  } end_list ();

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
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;
  struct hv_param *hp;
  bool has_kvm;
  int force_tcg;
  int force_kvm;
  const char *accel_val = "kvm:tcg";
  const char *cpu_model;
  CLEANUP_FREE char *append = NULL;
  CLEANUP_FREE_STRING_LIST char **argv = NULL;
  CLEANUP_FREE_STRING_LIST char **env = NULL;

  if (!g->nr_drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  guestfs_int_launch_send_progress (g, 0);

  /* Locate and/or build the appliance. */
  if (guestfs_int_build_appliance (g, &kernel, &initrd, &appliance) == -1)
    return -1;
  has_appliance_drive = appliance != NULL;

  guestfs_int_launch_send_progress (g, 3);

  debug (g, "begin testing qemu features");

  /* Get qemu help text and version. */
  if (data->qemu_data == NULL) {
    data->qemu_data = guestfs_int_test_qemu (g);
    if (data->qemu_data == NULL)
      goto cleanup0;
    data->qemu_version = guestfs_int_qemu_version (g, data->qemu_data);
    debug (g, "qemu version: %d.%d",
           data->qemu_version.v_major, data->qemu_version.v_minor);
    data->qemu_mandatory_locking =
      guestfs_int_qemu_mandatory_locking (g, data->qemu_data);
    debug (g, "qemu mandatory locking: %s",
           data->qemu_mandatory_locking ? "yes" : "no");
  }

  /* Work out if KVM is supported or if the user wants to force TCG. */
  has_kvm = guestfs_int_platform_has_kvm (g, data->qemu_data);
  debug (g, "qemu KVM: %s", has_kvm ? "enabled" : "disabled");

  force_tcg = guestfs_int_get_backend_setting_bool (g, "force_tcg");
  if (force_tcg == -1)
    return -1;
  else if (force_tcg)
    accel_val = "tcg";

  force_kvm = guestfs_int_get_backend_setting_bool (g, "force_kvm");
  if (force_kvm == -1)
    return -1;
  else if (force_kvm)
    accel_val = "kvm";

  if (force_kvm && force_tcg) {
    error (g, "Both force_kvm and force_tcg backend settings supplied.");
    return -1;
  }
  if (!has_kvm) {
    if (!force_tcg)
      debian_kvm_warning (g);
    if (force_kvm) {
      error (g, "force_kvm supplied but kvm not available.");
      return -1;
    }
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
  arg ("-global", VIRTIO_DEVICE_NAME ("virtio-blk") ".scsi=off");

  if (guestfs_int_qemu_supports (g, data->qemu_data, "-no-user-config"))
    flag ("-no-user-config");

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
    append_list_format ("accel=%s", accel_val);
#if defined(__i386__) || defined(__x86_64__)
    /* Tell seabios to send debug messages to the serial port.
     * This used to be done by sgabios.
     */
    if (g->verbose)
      append_list ("graphics=off");
#endif
  } end_list ();

  cpu_model = guestfs_int_get_cpu_model (has_kvm && !force_tcg);
  if (cpu_model) {
#if defined(__x86_64__)
    /* Temporary workaround for RHBZ#2082806 */
    if (STREQ (cpu_model, "max")) {
      start_list ("-cpu") {
        append_list (cpu_model);
        append_list ("la57=off");
      } end_list ();
    }
    else
#endif
      arg ("-cpu", cpu_model);
  }

  if (g->smp > 1)
    arg_format ("-smp", "%d", g->smp);

  arg_format ("-m", "%d", g->memsize);

  /* Force exit instead of reboot on panic */
  flag ("-no-reboot");

  /* These are recommended settings, see RHBZ#1053847. */
  arg ("-rtc", "driftfix=slew");
  if (guestfs_int_qemu_supports (g, data->qemu_data, "-no-hpet"))
    flag ("-no-hpet");
#if defined(__i386__) || defined(__x86_64__)
  if (guestfs_int_version_ge (&data->qemu_version, 1, 3, 0))
    arg ("-global", "kvm-pit.lost_tick_policy=discard");
#endif

  /* UEFI (firmware) if required. */
  if (guestfs_int_get_uefi (g, NULL, NULL, &uefi_code, &uefi_vars,
                            &uefi_flags) == -1)
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
                                        VIRTIO_DEVICE_NAME ("virtio-rng"))) {
    start_list ("-object") {
      append_list ("rng-random");
      append_list ("filename=/dev/urandom");
      append_list ("id=rng0");
    } end_list ();
    start_list ("-device") {
      append_list (VIRTIO_DEVICE_NAME ("virtio-rng"));
      append_list ("rng=rng0");
    } end_list ();
  }

  /* Create the virtio-scsi bus. */
  start_list ("-device") {
    append_list (VIRTIO_DEVICE_NAME ("virtio-scsi"));
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
#ifndef APPLIANCE_FORMAT_AUTO
      append_list ("format=raw");
#endif
    } end_list ();
    start_list ("-device") {
      append_list ("scsi-hd");
      append_list ("drive=appliance");
    } end_list ();
  }

  /* Create the virtio serial bus. */
  arg ("-device", VIRTIO_DEVICE_NAME ("virtio-serial"));

  /* Create the serial console. */
#ifndef __s390x__
  arg ("-serial", "stdio");
#else
  start_list ("-chardev") {
    append_list ("stdio");
    append_list ("id=charconsole0");
  } end_list ();
  start_list ("-device") {
    append_list ("sclpconsole");
    append_list ("chardev=charconsole0");
  } end_list ();
#endif

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
      append_list ("net=" NETWORK_ADDRESS "/" NETWORK_PREFIX);
    } end_list ();
    start_list ("-device") {
      append_list (VIRTIO_DEVICE_NAME ("virtio-net"));
      append_list ("netdev=usernet");
    } end_list ();
  }

  flags = 0;
  if (!has_kvm || force_tcg)
    flags |= APPLIANCE_COMMAND_LINE_IS_TCG;
  append = guestfs_int_appliance_command_line (g, appliance, flags);
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

  /* Create the environ for the child process. */
  env = guestfs_int_copy_environ (environ,
                                  "LC_ALL", "C",
                                  /* Prevents qemu opening /dev/dsp */
                                  "QEMU_AUDIO_DRV", "none",
                                  NULL);
  if (env == NULL)
    goto cleanup0;

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

    /* Unblock the SIGTERM signal since we will need to send that to
     * the subprocess (RHBZ#1460338).
     */
    guestfs_int_unblock_sigterm ();

    /* Dump the command line (after setting up stderr above). */
    if (g->verbose)
      qemuopts_to_channel (qopts, stderr);

    /* Put qemu in a new process group. */
    if (g->pgroup)
      setpgid (0, 0);

    execve (g->hv, argv, env);        /* Run qemu. */
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

      /* Unblock the SIGTERM signal since we will need to respond to
       * SIGTERM from the parent (RHBZ#1460338).
       */
      guestfs_int_unblock_sigterm ();

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
