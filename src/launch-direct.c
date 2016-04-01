/* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
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

#include <pcre.h>

#include <libxml/uri.h>

#include "cloexec.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

COMPILE_REGEXP (re_major_minor, "(\\d+)\\.(\\d+)", 0)

/* Per-handle data. */
struct backend_direct_data {
  pid_t pid;                  /* Qemu PID. */
  pid_t recoverypid;          /* Recovery process PID. */

  char *qemu_help;            /* Output of qemu -help. */
  char *qemu_devices;         /* Output of qemu -device ? */

  /* qemu version (0, 0 if unable to parse). */
  int qemu_version_major, qemu_version_minor;

  int virtio_scsi;        /* See function qemu_supports_virtio_scsi */
};

static int is_openable (guestfs_h *g, const char *path, int flags);
static char *make_appliance_dev (guestfs_h *g, int virtio_scsi);
static void print_qemu_command_line (guestfs_h *g, char **argv);
static int qemu_supports (guestfs_h *g, struct backend_direct_data *, const char *option);
static int qemu_supports_device (guestfs_h *g, struct backend_direct_data *, const char *device_name);
static int qemu_supports_virtio_scsi (guestfs_h *g, struct backend_direct_data *);

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

#ifdef QEMU_OPTIONS
/* Like 'add_cmdline' but allowing a shell-quoted string of zero or
 * more options.  XXX The unquoting is not very clever.
 */
static void
add_cmdline_shell_unquoted (guestfs_h *g, struct stringsbuf *sb,
                            const char *options)
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

    guestfs_int_add_string_nodup (g, sb,
				  safe_strndup (g, startp, endp-startp));

    options = nextp;
  }
}
#endif /* defined QEMU_OPTIONS */

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
  char guestfsd_sock[256];
  struct sockaddr_un addr;
  CLEANUP_FREE char *uefi_code = NULL, *uefi_vars = NULL;
  CLEANUP_FREE char *kernel = NULL, *dtb = NULL,
    *initrd = NULL, *appliance = NULL;
  int has_appliance_drive;
  CLEANUP_FREE char *appliance_dev = NULL;
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;
  struct drive *drv;
  size_t i;
  int virtio_scsi;
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
  if (guestfs_int_build_appliance (g, &kernel, &dtb, &initrd, &appliance) == -1)
    return -1;
  has_appliance_drive = appliance != NULL;

  TRACE0 (launch_build_appliance_end);

  guestfs_int_launch_send_progress (g, 3);

  debug (g, "begin testing qemu features");

  /* Get qemu help text and version. */
  if (qemu_supports (g, data, NULL) == -1)
    goto cleanup0;

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  snprintf (guestfsd_sock, sizeof guestfsd_sock, "%s/guestfsd.sock", g->tmpdir);
  unlink (guestfsd_sock);

  daemon_accept_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (daemon_accept_sock == -1) {
    perrorf (g, "socket");
    goto cleanup0;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, guestfsd_sock, UNIX_PATH_MAX);
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
   * devices.  The -global option must exist, but you can pass any
   * strings to it so we don't need to check for the specific virtio
   * feature.
   */
  if (qemu_supports (g, data, "-global")) {
    ADD_CMDLINE ("-global");
    ADD_CMDLINE (VIRTIO_BLK ".scsi=off");
  }

  if (qemu_supports (g, data, "-nodefconfig"))
    ADD_CMDLINE ("-nodefconfig");

  /* This oddly named option doesn't actually enable FIPS.  It just
   * causes qemu to do the right thing if FIPS is enabled in the
   * kernel.  So like libvirt, we pass it unconditionally.
   */
  if (qemu_supports (g, data, "-enable-fips"))
    ADD_CMDLINE ("-enable-fips");

  /* Newer versions of qemu (from around 2009/12) changed the
   * behaviour of monitors so that an implicit '-monitor stdio' is
   * assumed if we are in -nographic mode and there is no other
   * -monitor option.  Only a single stdio device is allowed, so
   * this broke the '-serial stdio' option.  There is a new flag
   * called -nodefaults which gets rid of all this default crud, so
   * let's use that to avoid this and any future surprises.
   */
  if (qemu_supports (g, data, "-nodefaults"))
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
  if (qemu_supports (g, data, "-no-hpet")) {
    ADD_CMDLINE ("-no-hpet");
  }
  if (data->qemu_version_major < 1 ||
      (data->qemu_version_major == 1 && data->qemu_version_minor <= 2))
    ADD_CMDLINE ("-no-kvm-pit-reinjection");
  else {
    /* New non-deprecated way, added in qemu >= 1.3. */
    ADD_CMDLINE ("-global");
    ADD_CMDLINE ("kvm-pit.lost_tick_policy=discard");
  }

  /* UEFI (firmware) if required. */
  if (guestfs_int_get_uefi (g, &uefi_code, &uefi_vars) == -1)
    goto cleanup0;
  if (uefi_code) {
    ADD_CMDLINE ("-drive");
    ADD_CMDLINE_PRINTF ("if=pflash,format=raw,file=%s,readonly", uefi_code);
    if (uefi_vars) {
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("if=pflash,format=raw,file=%s", uefi_vars);
    }
  }

  /* Kernel, DTB and initrd. */
  ADD_CMDLINE ("-kernel");
  ADD_CMDLINE (kernel);
  if (dtb) {
    ADD_CMDLINE ("-dtb");
    ADD_CMDLINE (dtb);
  }
  ADD_CMDLINE ("-initrd");
  ADD_CMDLINE (initrd);

  /* Add a random number generator (backend for virtio-rng).  This
   * isn't strictly necessary but means we won't need to hang around
   * when needing entropy.
   */
  if (qemu_supports_device (g, data, "virtio-rng-pci")) {
    ADD_CMDLINE ("-object");
    ADD_CMDLINE ("rng-random,filename=/dev/urandom,id=rng0");
    ADD_CMDLINE ("-device");
    ADD_CMDLINE ("virtio-rng-pci,rng=rng0");
  }

  /* Add drives */
  virtio_scsi = qemu_supports_virtio_scsi (g, data);

  if (virtio_scsi) {
    /* Create the virtio-scsi bus. */
    ADD_CMDLINE ("-device");
    ADD_CMDLINE (VIRTIO_SCSI ",id=scsi");
  }

  ITER_DRIVES (g, i, drv) {
    CLEANUP_FREE char *file = NULL, *escaped_file = NULL, *param = NULL;

    if (!drv->overlay) {
      const char *discard_mode = "";
      int major = data->qemu_version_major, minor = data->qemu_version_minor;
      unsigned long qemu_version = major * 1000000 + minor * 1000;

      switch (drv->discard) {
      case discard_disable:
        /* Since the default is always discard=ignore, don't specify it
         * on the command line.  This also avoids unnecessary breakage
         * with qemu < 1.5 which didn't have the option at all.
         */
        break;
      case discard_enable:
        if (!guestfs_int_discard_possible (g, drv, qemu_version))
          goto cleanup0;
        /*FALLTHROUGH*/
      case discard_besteffort:
        /* I believe from reading the code that this is always safe as
         * long as qemu >= 1.5.
         */
        if (major > 1 || (major == 1 && minor >= 5))
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
     * virtio-scsi if available.  Otherwise default to virtio-blk.
     */
    if (drv->iface && STREQ (drv->iface, "virtio")) /* virtio-blk */
      goto virtio_blk;
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
    else if (virtio_scsi) {
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("%s,if=none" /* sic */, param);
      ADD_CMDLINE ("-device");
      ADD_CMDLINE_PRINTF ("scsi-hd,drive=hd%zu", i);
    }
    else {
    virtio_blk:
      ADD_CMDLINE ("-drive");
      ADD_CMDLINE_PRINTF ("%s,if=none" /* sic */, param);
      ADD_CMDLINE ("-device");
      ADD_CMDLINE_PRINTF (VIRTIO_BLK ",drive=hd%zu", i);
    }
  }

  /* Add the ext2 appliance drive (after all the drives). */
  if (has_appliance_drive) {
    ADD_CMDLINE ("-drive");
    ADD_CMDLINE_PRINTF ("file=%s,snapshot=on,id=appliance,"
                        "cache=unsafe,if=none,format=raw",
                        appliance);

    if (virtio_scsi) {
      ADD_CMDLINE ("-device");
      ADD_CMDLINE ("scsi-hd,drive=appliance");
    }
    else {
      ADD_CMDLINE ("-device");
      ADD_CMDLINE (VIRTIO_BLK ",drive=appliance");
    }

    appliance_dev = make_appliance_dev (g, virtio_scsi);
  }

  /* Create the virtio serial bus. */
  ADD_CMDLINE ("-device");
  ADD_CMDLINE (VIRTIO_SERIAL);

  /* Create the serial console. */
  ADD_CMDLINE ("-serial");
  ADD_CMDLINE ("stdio");

  if (g->verbose &&
      qemu_supports_device (g, data, "Serial Graphics Adapter")) {
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
  ADD_CMDLINE_PRINTF ("socket,path=%s,id=channel0", guestfsd_sock);
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

  /* Add the extra options for the qemu command line specified
   * at configure time.
   */
#ifdef QEMU_OPTIONS
  if (STRNEQ (QEMU_OPTIONS, ""))
    add_cmdline_shell_unquoted (g, &cmdline, QEMU_OPTIONS);
#endif

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

static void parse_qemu_version (guestfs_h *g, struct backend_direct_data *data);
static void read_all (guestfs_h *g, void *retv, const char *buf, size_t len);

/* Test qemu binary (or wrapper) runs, and do 'qemu -help' so we know
 * the version of qemu what options this qemu supports.
 */
static int
test_qemu (guestfs_h *g, struct backend_direct_data *data)
{
  CLEANUP_CMD_CLOSE struct command *cmd1 = guestfs_int_new_command (g);
  CLEANUP_CMD_CLOSE struct command *cmd2 = guestfs_int_new_command (g);
  int r;

  free (data->qemu_help);
  data->qemu_help = NULL;
  free (data->qemu_devices);
  data->qemu_devices = NULL;

  guestfs_int_cmd_add_arg (cmd1, g->hv);
  guestfs_int_cmd_add_arg (cmd1, "-display");
  guestfs_int_cmd_add_arg (cmd1, "none");
  guestfs_int_cmd_add_arg (cmd1, "-help");
  guestfs_int_cmd_set_stdout_callback (cmd1, read_all, &data->qemu_help,
				       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd1);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  parse_qemu_version (g, data);

  guestfs_int_cmd_add_arg (cmd2, g->hv);
  guestfs_int_cmd_add_arg (cmd2, "-display");
  guestfs_int_cmd_add_arg (cmd2, "none");
  guestfs_int_cmd_add_arg (cmd2, "-machine");
  guestfs_int_cmd_add_arg (cmd2,
#ifdef MACHINE_TYPE
                           MACHINE_TYPE ","
#endif
                           "accel=kvm:tcg");
  guestfs_int_cmd_add_arg (cmd2, "-device");
  guestfs_int_cmd_add_arg (cmd2, "?");
  guestfs_int_cmd_clear_capture_errors (cmd2);
  guestfs_int_cmd_set_stderr_to_stdout (cmd2);
  guestfs_int_cmd_set_stdout_callback (cmd2, read_all, &data->qemu_devices,
				       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd2);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  return 0;

 error:
  if (r == -1)
    return -1;

  guestfs_int_external_command_failed (g, r, g->hv, NULL);
  return -1;
}

/* Parse the first line of data->qemu_help (if not NULL) into the
 * major and minor version of qemu, but don't fail if parsing is not
 * possible.
 */
static void
parse_qemu_version (guestfs_h *g, struct backend_direct_data *data)
{
  CLEANUP_FREE char *major_s = NULL, *minor_s = NULL;
  int major_i, minor_i;

  data->qemu_version_major = 0;
  data->qemu_version_minor = 0;

  if (!data->qemu_help)
    return;

  if (!match2 (g, data->qemu_help, re_major_minor, &major_s, &minor_s)) {
  parse_failed:
    debug (g, "%s: failed to parse qemu version string from the first line of the output of '%s -help'.  When reporting this bug please include the -help output.",
           __func__, g->hv);
    return;
  }

  major_i = guestfs_int_parse_unsigned_int (g, major_s);
  if (major_i == -1)
    goto parse_failed;

  minor_i = guestfs_int_parse_unsigned_int (g, minor_s);
  if (minor_i == -1)
    goto parse_failed;

  data->qemu_version_major = major_i;
  data->qemu_version_minor = minor_i;

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
qemu_supports (guestfs_h *g, struct backend_direct_data *data,
               const char *option)
{
  if (!data->qemu_help) {
    if (test_qemu (g, data) == -1)
      return -1;
  }

  if (option == NULL)
    return 1;

  return strstr (data->qemu_help, option) != NULL;
}

/* Test if device is supported by qemu (currently just greps the -device ?
 * output).
 */
static int
qemu_supports_device (guestfs_h *g, struct backend_direct_data *data,
                      const char *device_name)
{
  if (!data->qemu_devices) {
    if (test_qemu (g, data) == -1)
      return -1;
  }

  return strstr (data->qemu_devices, device_name) != NULL;
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
old_or_broken_virtio_scsi (guestfs_h *g, struct backend_direct_data *data)
{
  /* qemu 1.1 claims to support virtio-scsi but in reality it's broken. */
  if (data->qemu_version_major == 1 && data->qemu_version_minor < 2)
    return 1;

  return 0;
}

/* Returns 1 = use virtio-scsi, or 0 = use virtio-blk. */
static int
qemu_supports_virtio_scsi (guestfs_h *g, struct backend_direct_data *data)
{
  int r;

  if (!data->qemu_help) {
    if (test_qemu (g, data) == -1)
      return 0;                 /* safe option? */
  }

  /* data->virtio_scsi has these values:
   *   0 = untested (after handle creation)
   *   1 = supported
   *   2 = not supported (use virtio-blk)
   *   3 = test failed (use virtio-blk)
   */
  if (data->virtio_scsi == 0) {
    if (old_or_broken_virtio_scsi (g, data))
      data->virtio_scsi = 2;
    else {
      r = qemu_supports_device (g, data, VIRTIO_SCSI);
      if (r > 0)
        data->virtio_scsi = 1;
      else if (r == 0)
        data->virtio_scsi = 2;
      else
        data->virtio_scsi = 3;
    }
  }

  return data->virtio_scsi == 1;
}

/**
 * Escape a qemu parameter.
 *
 * Every C<,> becomes C<,,>.  The caller must free the returned string.
 */
char *
guestfs_int_qemu_escape_param (guestfs_h *g, const char *param)
{
  size_t i, len = strlen (param);
  char *p, *ret;

  ret = p = safe_malloc (g, len*2 + 1); /* max length of escaped name*/
  for (i = 0; i < len; ++i) {
    *p++ = param[i];
    if (param[i] == ',')
      *p++ = ',';
  }
  *p = '\0';

  return ret;
}

static char *
make_uri (guestfs_h *g, const char *scheme, const char *user,
          const char *password,
          struct drive_server *server, const char *path)
{
  xmlURI uri = { .scheme = (char *) scheme,
                 .user = (char *) user };
  CLEANUP_FREE char *query = NULL;
  CLEANUP_FREE char *pathslash = NULL;
  CLEANUP_FREE char *userauth = NULL;

  /* Need to add a leading '/' to URI paths since xmlSaveUri doesn't. */
  if (path != NULL && path[0] != '/') {
    pathslash = safe_asprintf (g, "/%s", path);
    uri.path = pathslash;
  }
  else
    uri.path = (char *) path;

  /* Rebuild user:password. */
  if (user != NULL && password != NULL) {
    /* Keep the string in an own variable so it can be freed automatically. */
    userauth = safe_asprintf (g, "%s:%s", user, password);
    uri.user = userauth;
  }

  switch (server->transport) {
  case drive_transport_none:
  case drive_transport_tcp:
    uri.server = server->u.hostname;
    uri.port = server->port;
    break;
  case drive_transport_unix:
    query = safe_asprintf (g, "socket=%s", server->u.socket);
    uri.query_raw = query;
    break;
  }

  return (char *) xmlSaveUri (&uri);
}

/* Useful function to format a drive + protocol for qemu.  Also shared
 * with launch-libvirt.c.
 *
 * Note that the qemu parameter is the bit after "file=".  It is not
 * escaped here, but would usually be escaped if passed to qemu as
 * part of a full -drive parameter (but not for qemu-img).
 */
char *
guestfs_int_drive_source_qemu_param (guestfs_h *g, const struct drive_source *src)
{
  char *path;

  switch (src->protocol) {
  case drive_protocol_file:
    /* We have to convert the path to an absolute path, since
     * otherwise qemu will look for the backing file relative to the
     * overlay (which is located in g->tmpdir).
     *
     * As a side-effect this deals with paths that contain ':' since
     * qemu will not process the ':' if the path begins with '/'.
     */
    path = realpath (src->u.path, NULL);
    if (path == NULL) {
      perrorf (g, _("realpath: could not convert '%s' to absolute path"),
               src->u.path);
      return NULL;
    }
    return path;

  case drive_protocol_ftp:
    return make_uri (g, "ftp", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_ftps:
    return make_uri (g, "ftps", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_gluster:
    switch (src->servers[0].transport) {
    case drive_transport_none:
      return make_uri (g, "gluster", NULL, NULL,
                       &src->servers[0], src->u.exportname);
    case drive_transport_tcp:
      return make_uri (g, "gluster+tcp", NULL, NULL,
                       &src->servers[0], src->u.exportname);
    case drive_transport_unix:
      return make_uri (g, "gluster+unix", NULL, NULL,
                       &src->servers[0], NULL);
    }

  case drive_protocol_http:
    return make_uri (g, "http", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_https:
    return make_uri (g, "https", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_iscsi: {
    CLEANUP_FREE char *escaped_hostname = NULL;
    CLEANUP_FREE char *escaped_target = NULL;
    CLEANUP_FREE char *userauth = NULL;
    char port_str[16];
    char *ret;

    escaped_hostname =
      (char *) xmlURIEscapeStr(BAD_CAST src->servers[0].u.hostname,
                               BAD_CAST "");
    /* The target string must keep slash as it is, as exportname contains
     * "iqn/lun".
     */
    escaped_target =
      (char *) xmlURIEscapeStr(BAD_CAST src->u.exportname, BAD_CAST "/");
    if (src->username != NULL && src->secret != NULL)
      userauth = safe_asprintf (g, "%s%%%s@", src->username, src->secret);
    if (src->servers[0].port != 0)
      snprintf (port_str, sizeof port_str, ":%d", src->servers[0].port);

    ret = safe_asprintf (g, "iscsi://%s%s%s/%s",
                         userauth != NULL ? userauth : "",
                         escaped_hostname,
                         src->servers[0].port != 0 ? port_str : "",
                         escaped_target);

    return ret;
  }

  case drive_protocol_nbd: {
    CLEANUP_FREE char *p = NULL;
    char *ret;

    switch (src->servers[0].transport) {
    case drive_transport_none:
    case drive_transport_tcp:
      p = safe_asprintf (g, "nbd:%s:%d",
                         src->servers[0].u.hostname, src->servers[0].port);
      break;
    case drive_transport_unix:
      p = safe_asprintf (g, "nbd:unix:%s", src->servers[0].u.socket);
      break;
    }
    assert (p);

    if (STREQ (src->u.exportname, ""))
      ret = safe_strdup (g, p);
    else
      ret = safe_asprintf (g, "%s:exportname=%s", p, src->u.exportname);

    return ret;
  }

  case drive_protocol_rbd: {
    CLEANUP_FREE char *mon_host = NULL, *username = NULL, *secret = NULL;
    const char *auth;
    size_t n = 0;
    size_t i, j;

    /* build the list of all the mon hosts */
    for (i = 0; i < src->nr_servers; i++) {
      n += strlen (src->servers[i].u.hostname);
      n += 8; /* for slashes, colons, & port numbers */
    }
    n++; /* for \0 */
    mon_host = safe_malloc (g, n);
    n = 0;
    for (i = 0; i < src->nr_servers; i++) {
      CLEANUP_FREE char *port = NULL;

      for (j = 0; j < strlen (src->servers[i].u.hostname); j++)
        mon_host[n++] = src->servers[i].u.hostname[j];
      mon_host[n++] = '\\';
      mon_host[n++] = ':';
      port = safe_asprintf (g, "%d", src->servers[i].port);
      for (j = 0; j < strlen (port); j++)
        mon_host[n++] = port[j];

      /* join each host with \; */
      if (i != src->nr_servers - 1) {
        mon_host[n++] = '\\';
        mon_host[n++] = ';';
      }
    }
    mon_host[n] = '\0';

    if (src->username)
      username = safe_asprintf (g, ":id=%s", src->username);
    if (src->secret)
      secret = safe_asprintf (g, ":key=%s", src->secret);
    if (username || secret)
      auth = ":auth_supported=cephx\\;none";
    else
      auth = ":auth_supported=none";

    return safe_asprintf (g, "rbd:%s%s%s%s%s%s",
                          src->u.exportname,
                          src->nr_servers > 0 ? ":mon_host=" : "",
                          src->nr_servers > 0 ? mon_host : "",
                          username ? username : "",
                          auth,
                          secret ? secret : "");
  }

  case drive_protocol_sheepdog:
    if (src->nr_servers == 0)
      return safe_asprintf (g, "sheepdog:%s", src->u.exportname);
    else                        /* XXX How to pass multiple hosts? */
      return safe_asprintf (g, "sheepdog:%s:%d:%s",
                            src->servers[0].u.hostname, src->servers[0].port,
                            src->u.exportname);

  case drive_protocol_ssh:
    return make_uri (g, "ssh", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_tftp:
    return make_uri (g, "tftp", src->username, src->secret,
                     &src->servers[0], src->u.exportname);
  }

  abort ();
}

/* Test if discard is both supported by qemu AND possible with the
 * underlying file or device.  This returns 1 if discard is possible.
 * It returns 0 if not possible and sets the error to the reason why.
 *
 * This function is called when the user set discard == "enable".
 *
 * qemu_version is the version of qemu in the form returned by libvirt:
 * major * 1,000,000 + minor * 1,000 + release
 */
bool
guestfs_int_discard_possible (guestfs_h *g, struct drive *drv,
			      unsigned long qemu_version)
{
  /* qemu >= 1.5.  This was the first version that supported the
   * discard option on -drive at all.
   */
  bool qemu15 = qemu_version >= 1005000;

  if (!qemu15)
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu < 1.5"));

  /* If it's an overlay, discard is not possible (on the underlying
   * file).  This has probably been caught earlier since we already
   * checked that the drive is !readonly.  Nevertheless ...
   */
  if (drv->overlay)
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "the drive has a read-only overlay"));

  /* Look at the source format. */
  if (drv->src.format == NULL) {
    /* We could autodetect the format, but we don't ... yet. XXX */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "you have to specify the format of the file"));
  }
  else if (STREQ (drv->src.format, "raw"))
    /* OK */ ;
  else if (STREQ (drv->src.format, "qcow2"))
    /* OK */ ;
  else {
    /* It's possible in future other formats will support discard, but
     * currently (qemu 1.7) none of them do.
     */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu does not support discard for '%s' format files"),
                   drv->src.format);
  }

  switch (drv->src.protocol) {
    /* Protocols which support discard. */
  case drive_protocol_file:
  case drive_protocol_gluster:
  case drive_protocol_iscsi:
  case drive_protocol_nbd:
  case drive_protocol_rbd:
  case drive_protocol_sheepdog: /* XXX depends on server version */
    break;

    /* Protocols which don't support discard. */
  case drive_protocol_ftp:
  case drive_protocol_ftps:
  case drive_protocol_http:
  case drive_protocol_https:
  case drive_protocol_ssh:
  case drive_protocol_tftp:
    NOT_SUPPORTED (g, -1,
                   _("discard cannot be enabled on this drive: "
                     "protocol '%s' does not support discard"),
                   guestfs_int_drive_protocol_to_string (drv->src.protocol));
  }

  return true;
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

  free (data->qemu_help);
  data->qemu_help = NULL;
  free (data->qemu_devices);
  data->qemu_devices = NULL;

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
  struct backend_direct_data *data = datav;

  if (qemu_supports_virtio_scsi (g, data))
    return 255;
  else
    return 27;                  /* conservative estimate */
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
