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
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <signal.h>
#include <assert.h>

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
#include "ignore-value.h"
#include "glthread/lock.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int launch_appliance (guestfs_h *g);
static int64_t timeval_diff (const struct timeval *x, const struct timeval *y);
static void print_qemu_command_line (guestfs_h *g, char **argv);
static int connect_unix_socket (guestfs_h *g, const char *sock);
static int qemu_supports (guestfs_h *g, const char *option);
static char *qemu_drive_param (guestfs_h *g, const struct drive *drv);

#if 0
static int qemu_supports_re (guestfs_h *g, const pcre *option_regex);

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
}

static void
free_regexps (void)
{
}
#endif

/* Functions to add a string to the current command line. */
static void
alloc_cmdline (guestfs_h *g)
{
  if (g->cmdline == NULL) {
    /* g->cmdline[0] is reserved for argv[0], set in guestfs_launch. */
    g->cmdline_size = 1;
    g->cmdline = safe_malloc (g, sizeof (char *));
    g->cmdline[0] = NULL;
  }
}

static void
incr_cmdline_size (guestfs_h *g)
{
  alloc_cmdline (g);
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

struct drive **
guestfs___checkpoint_drives (guestfs_h *g)
{
  struct drive **i = &g->drives;
  while (*i != NULL) i = &((*i)->next);
  return i;
}

void
guestfs___rollback_drives (guestfs_h *g, struct drive **i)
{
  guestfs___free_drives(i);
}

/* Internal command to return the command line. */
char **
guestfs__debug_cmdline (guestfs_h *g)
{
  size_t i;
  char **r;

  alloc_cmdline (g);

  r = safe_malloc (g, sizeof (char *) * (g->cmdline_size + 1));
  r[0] = safe_strdup (g, g->qemu); /* g->cmdline[0] is always NULL */

  for (i = 1; i < g->cmdline_size; ++i)
    r[i] = safe_strdup (g, g->cmdline[i]);

  r[g->cmdline_size] = NULL;

  return r;                     /* caller frees */
}

/* Internal command to return the list of drives. */
char **
guestfs__debug_drives (guestfs_h *g)
{
  size_t i, count;
  char **ret;
  struct drive *drv;

  for (count = 0, drv = g->drives; drv; count++, drv = drv->next)
    ;

  ret = safe_malloc (g, sizeof (char *) * (count + 1));

  for (i = 0, drv = g->drives; drv; i++, drv = drv->next)
    ret[i] = qemu_drive_param (g, drv);

  ret[count] = NULL;

  return ret;                   /* caller frees */
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

/* cache=off improves reliability in the event of a host crash.
 *
 * However this option causes qemu to try to open the file with
 * O_DIRECT.  This fails on some filesystem types (notably tmpfs).
 * So we check if we can open the file with or without O_DIRECT,
 * and use cache=off (or not) accordingly.
 *
 * NB: This function is only called on the !readonly path.  We must
 * try to open with O_RDWR to test that the file is readable and
 * writable here.
 */
static int
test_cache_off (guestfs_h *g, const char *filename)
{
  int fd = open (filename, O_RDWR|O_DIRECT);
  if (fd >= 0) {
    close (fd);
    return 1;
  }

  fd = open (filename, O_RDWR);
  if (fd >= 0) {
    close (fd);
    return 0;
  }

  perrorf (g, "%s", filename);
  return -1;
}

/* Check string parameter matches ^[-_[:alnum:]]+$ (in C locale). */
static int
valid_format_iface (const char *str)
{
  size_t len = strlen (str);

  if (len == 0)
    return 0;

  while (len > 0) {
    char c = *str++;
    len--;
    if (c != '-' && c != '_' && !c_isalnum (c))
      return 0;
  }
  return 1;
}

static int
check_path (guestfs_h *g, const char *filename)
{
  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }
  return 0;
}

int
guestfs__add_drive_opts (guestfs_h *g, const char *filename,
                         const struct guestfs_add_drive_opts_argv *optargs)
{
  int readonly;
  char *format;
  char *iface;
  char *name;
  char *abs_path = NULL;
  int use_cache_off;
  int check_duplicate;

  if (check_path(g, filename) == -1)
    return -1;

  readonly = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK
             ? optargs->readonly : 0;
  format = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK
           ? safe_strdup (g, optargs->format) : NULL;
  iface = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
          ? safe_strdup (g, optargs->iface) : safe_strdup (g, DRIVE_IF);
  name = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_NAME_BITMASK
          ? safe_strdup (g, optargs->name) : NULL;

  if (format && !valid_format_iface (format)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "format");
    goto err_out;
  }
  if (!valid_format_iface (iface)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "iface");
    goto err_out;
  }

  /* For writable files, see if we can use cache=off.  This also
   * checks for the existence of the file.  For readonly we have
   * to do the check explicitly.
   */
  use_cache_off = readonly ? 0 : test_cache_off (g, filename);
  if (use_cache_off == -1)
    goto err_out;

  if (readonly) {
    if (access (filename, R_OK) == -1) {
      perrorf (g, "%s", filename);
      goto err_out;
    }
  }

  /* Make the path canonical, so we can check if the user is trying to
   * add the same path twice.  Allow /dev/null to be added multiple
   * times, in accordance with traditional usage.
   */
  abs_path = realpath (filename, NULL);
  check_duplicate = STRNEQ (abs_path, "/dev/null");

  struct drive **i = &(g->drives);
  while (*i != NULL) {
    if (check_duplicate && STREQ((*i)->path, abs_path)) {
      error (g, _("drive %s can't be added twice"), abs_path);
      goto err_out;
    }
    i = &((*i)->next);
  }

  *i = safe_malloc (g, sizeof (struct drive));
  (*i)->next = NULL;
  (*i)->path = safe_strdup (g, abs_path);
  (*i)->readonly = readonly;
  (*i)->format = format;
  (*i)->iface = iface;
  (*i)->name = name;
  (*i)->use_cache_off = use_cache_off;

  free (abs_path);
  return 0;

err_out:
  free (format);
  free (iface);
  free (name);
  free (abs_path);
  return -1;
}

int
guestfs__add_drive (guestfs_h *g, const char *filename)
{
  struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = 0,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_ro (guestfs_h *g, const char *filename)
{
  struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .readonly = 1,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_with_if (guestfs_h *g, const char *filename,
                            const char *iface)
{
  struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK,
    .iface = iface,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_ro_with_if (guestfs_h *g, const char *filename,
                               const char *iface)
{
  struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
             | GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .iface = iface,
    .readonly = 1,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_cdrom (guestfs_h *g, const char *filename)
{
  if (check_path(g, filename) == -1)
    return -1;

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  return guestfs__config (g, "-cdrom", filename);
}

static int is_openable (guestfs_h *g, const char *path, int flags);

int
guestfs__launch (guestfs_h *g)
{
  /* Configured? */
  if (g->state != CONFIG) {
    error (g, _("the libguestfs handle has already been launched"));
    return -1;
  }

  TRACE0 (launch_start);

  /* Make the temporary directory. */
  if (!g->tmpdir) {
    TMP_TEMPLATE_ON_STACK (dir_template);
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), dir_template);
      return -1;
    }
  }

  /* Allow anyone to read the temporary directory.  The socket in this
   * directory won't be readable but anyone can see it exists if they
   * want. (RHBZ#610880).
   */
  if (chmod (g->tmpdir, 0755) == -1)
    warning (g, "chmod: %s: %m (ignored)", g->tmpdir);

  /* Launch the appliance or attach to an existing daemon. */
  switch (g->attach_method) {
  case ATTACH_METHOD_APPLIANCE:
    return launch_appliance (g);

  case ATTACH_METHOD_UNIX:
    return connect_unix_socket (g, g->attach_method_arg);

  default:
    abort ();
  }
}

/* RHBZ#790721: It makes no sense to have multiple threads racing to
 * build the appliance from within a single process, and the code
 * isn't safe for that anyway.  Therefore put a thread lock around
 * appliance building.
 */
gl_lock_define_initialized (static, building_lock);

static int
launch_appliance (guestfs_h *g)
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

  /* Start the clock ... */
  gettimeofday (&g->launch_t, NULL);
  guestfs___launch_send_progress (g, 0);

  TRACE0 (launch_build_appliance_start);

  /* Locate and/or build the appliance. */
  char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  gl_lock_lock (building_lock);
  if (guestfs___build_appliance (g, &kernel, &initrd, &appliance) == -1) {
    gl_lock_unlock (building_lock);
    return -1;
  }
  gl_lock_unlock (building_lock);

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

    /* Set up the full command line.  Do this in the subprocess so we
     * don't need to worry about cleaning up.
     */

    /* Set g->cmdline[0] to the name of the qemu process.  However
     * it is possible that no g->cmdline has been allocated yet so
     * we must do that first.
     */
    alloc_cmdline (g);
    g->cmdline[0] = g->qemu;

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
    while (drv != NULL) {
      /* Construct the final -drive parameter. */
      char *buf = qemu_drive_param (g, drv);

      add_cmdline (g, "-drive");
      add_cmdline (g, buf);
      free (buf);

      drv = drv->next;
    }

    if (qemu_supports (g, "-nodefconfig"))
      add_cmdline (g, "-nodefconfig");

    /* The qemu -machine option (added 2010-12) is a bit more sane
     * since it falls back through various different acceleration
     * modes, so try that first (thanks Markus Armbruster).
     */
    if (qemu_supports (g, "-machine")) {
      add_cmdline (g, "-machine");
#if QEMU_MACHINE_TYPE_IS_BROKEN
      /* Workaround for qemu 0.15: We have to add the '[type=]pc'
       * since there is no default.  This is not a permanent solution
       * because this only works on PC-like hardware.  Other platforms
       * like ppc would need a different machine type.
       *
       * This bug is fixed in qemu commit 2645c6dcaf6ea2a51a, and was
       * not a problem in qemu < 0.15.
       */
      add_cmdline (g, "pc,accel=kvm:tcg");
#else
      add_cmdline (g, "accel=kvm:tcg");
#endif
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
          is_openable (g, "/dev/kvm", O_RDWR))
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
      add_cmdline (g, NET_IF ",netdev=usernet");
    }

#define LINUX_CMDLINE							\
    "panic=1 "         /* force kernel to panic if daemon exits */	\
    "console=ttyS0 "   /* serial console */				\
    "udevtimeout=300 " /* good for very slow systems (RHBZ#480319) */	\
    "no_timer_check "  /* fix for RHBZ#502058 */                        \
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
      print_qemu_command_line (g, g->cmdline);

    /* Put qemu in a new process group. */
    if (g->pgroup)
      setpgid (0, 0);

    setenv ("LC_ALL", "C", 1);

    TRACE0 (launch_run_qemu);

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
  free (appliance);
  appliance = NULL;

  /* Fork the recovery process off which will kill qemu if the parent
   * process fails to do so (eg. if the parent segfaults).
   */
  g->recoverypid = -1;
  if (g->recovery_proc) {
    r = fork ();
    if (r == 0) {
      int i, fd, max_fd;
      struct sigaction sa;
      pid_t qemu_pid = g->pid;
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

  /* NB: We reach here just because qemu has opened the socket.  It
   * does not mean the daemon is up until we read the
   * GUESTFS_LAUNCH_FLAG below.  Failures in qemu startup can still
   * happen even if we reach here, even early failures like not being
   * able to open a drive.
   */

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
    close (wfd[1]);
    close (rfd[0]);
  }
  if (g->pid > 0) kill (g->pid, 9);
  if (g->recoverypid > 0) kill (g->recoverypid, 9);
  if (g->pid > 0) waitpid (g->pid, NULL, 0);
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

/* Alternate attach method: instead of launching the appliance,
 * connect to an existing unix socket.
 */
static int
connect_unix_socket (guestfs_h *g, const char *sockpath)
{
  int r;
  struct sockaddr_un addr;

  /* Start the clock ... */
  gettimeofday (&g->launch_t, NULL);

  /* Set these to nothing so we don't try to kill random processes or
   * read from random file descriptors.
   */
  g->pid = 0;
  g->recoverypid = 0;
  g->fd[0] = -1;
  g->fd[1] = -1;

  if (g->verbose)
    guestfs___print_timestamped_message (g, "connecting to %s", sockpath);

  g->sock = socket (AF_UNIX, SOCK_STREAM, 0);
  if (g->sock == -1) {
    perrorf (g, "socket");
    return -1;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, sockpath, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  g->state = LAUNCHING;

  if (connect (g->sock, &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup;
  }

  uint32_t size;
  void *buf = NULL;
  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) return -1;

  if (size != GUESTFS_LAUNCH_FLAG) {
    error (g, _("guestfs_launch failed, unexpected initial message from guestfsd"));
    goto cleanup;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "connected");

  if (g->state != READY) {
    error (g, _("contacted guestfsd, but state != READY"));
    goto cleanup;
  }

  return 0;

 cleanup:
  close (g->sock);
  return -1;
}

/* launch (of the appliance) generates approximate progress
 * messages.  Currently these are defined as follows:
 *
 *    0 / 12: launch clock starts
 *    3 / 12: appliance created
 *    6 / 12: detected that guest kernel started
 *    9 / 12: detected that /init script is running
 *   12 / 12: launch completed successfully
 *
 * Notes:
 * (1) This is not a documented ABI and the behaviour may be changed
 * or removed in future.
 * (2) Messages are only sent if more than 5 seconds has elapsed
 * since the launch clock started.
 * (3) There is a gross hack in proto.c to make this work.
 */
void
guestfs___launch_send_progress (guestfs_h *g, int perdozen)
{
  struct timeval tv;

  gettimeofday (&tv, NULL);
  if (timeval_diff (&g->launch_t, &tv) >= 5000) {
    guestfs_progress progress_message =
      { .proc = 0, .serial = 0, .position = perdozen, .total = 12 };

    guestfs___progress_message_callback (g, &progress_message);
  }
}

/* Return the location of the tmpdir (eg. "/tmp") and allow users
 * to override it at runtime using $TMPDIR.
 * http://www.pathname.com/fhs/pub/fhs-2.3.html#TMPTEMPORARYFILES
 */
const char *
guestfs_tmpdir (void)
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

/* Return the location of the persistent tmpdir (eg. "/var/tmp") and
 * allow users to override it at runtime using $TMPDIR.
 * http://www.pathname.com/fhs/pub/fhs-2.3.html#VARTMPTEMPORARYFILESPRESERVEDBETWEE
 */
const char *
guestfs___persistent_tmpdir (void)
{
  const char *tmpdir;

  tmpdir = "/var/tmp";

  const char *t = getenv ("TMPDIR");
  if (t) tmpdir = t;

  return tmpdir;
}

/* Recursively remove a temporary directory.  If removal fails, just
 * return (it's a temporary directory so it'll eventually be cleaned
 * up by a temp cleaner).  This is done using "rm -rf" because that's
 * simpler and safer, but we have to exec to ensure that paths don't
 * need to be quoted.
 */
void
guestfs___remove_tmpdir (const char *dir)
{
  pid_t pid = fork ();

  if (pid == -1) {
    perror ("remove tmpdir: fork");
    return;
  }
  if (pid == 0) {
    execlp ("rm", "rm", "-rf", dir, NULL);
    perror ("remove tmpdir: exec: rm");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  if (waitpid (pid, NULL, 0) == -1) {
    perror ("remove tmpdir: waitpid");
    return;
  }
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

/* Note that since this calls 'debug' it should only be called
 * from the parent process.
 */
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

  debug (g, "[%05" PRIi64 "ms] %s", timeval_diff (&g->launch_t, &tv), msg);

  free (msg);
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
  fprintf (stderr, "[%05" PRIi64 "ms] ", timeval_diff (&g->launch_t, &tv));

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

  free (g->qemu_help);
  g->qemu_help = NULL;
  free (g->qemu_version);
  g->qemu_version = NULL;

  snprintf (cmd, sizeof cmd, "LC_ALL=C '%s' -nographic -help", g->qemu);

  /* qemu -help should always work (qemu -version OTOH wasn't
   * supported by qemu 0.9).  If this command doesn't work then it
   * probably indicates that the qemu binary is missing.
   */
  if (test_qemu_cmd (g, cmd, &g->qemu_help) == -1) {
    error (g, _("command failed: %s\n\nIf qemu is located on a non-standard path, try setting the LIBGUESTFS_QEMU\nenvironment variable.  There may also be errors printed above."),
           cmd);
    return -1;
  }

  snprintf (cmd, sizeof cmd, "LC_ALL=C '%s' -nographic -version 2>/dev/null",
            g->qemu);

  /* Intentionally ignore errors from qemu -version. */
  ignore_value (test_qemu_cmd (g, cmd, &g->qemu_version));

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

#if 0
/* As above but using a regex instead of a fixed string. */
static int
qemu_supports_re (guestfs_h *g, const pcre *option_regex)
{
  if (!g->qemu_help) {
    if (test_qemu (g) == -1)
      return -1;
  }

  return match (g, g->qemu_help, option_regex);
}
#endif

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

static char *
qemu_drive_param (guestfs_h *g, const struct drive *drv)
{
  size_t len = 64;
  char *r;

  len += strlen (drv->path);
  len += strlen (drv->iface);
  if (drv->format)
    len += strlen (drv->format);

  r = safe_malloc (g, len);

  snprintf (r, len, "file=%s%s%s%s%s,if=%s",
            drv->path,
            drv->readonly ? ",snapshot=on" : "",
            drv->use_cache_off ? ",cache=off" : "",
            drv->format ? ",format=" : "",
            drv->format ? drv->format : "",
            drv->iface);

  return r;                     /* caller frees */
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

  debug (g, "sending SIGTERM to process %d", g->pid);

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
