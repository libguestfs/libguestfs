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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdbool.h>
#include <unistd.h>
#include <limits.h>
#include <fcntl.h>
#include <grp.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>
#include <string.h>
#include <libintl.h>
#include <sys/un.h>  /* sockaddr_un */

#ifdef HAVE_LIBVIRT
#include <libvirt/virterror.h>
#endif

#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>

#if HAVE_LIBSELINUX
#include <selinux/selinux.h>
#include <selinux/context.h>
#endif

#include "base64.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

#include "libxml2-writer-macros.h"

/* This macro is used by the macros in "libxml2-writer-macros.h"
 * when an error occurs.
 */
#define xml_error(fn)                                                   \
  perrorf (g, _("%s:%d: error constructing libvirt XML near call to \"%s\""), \
           __FILE__, __LINE__, (fn));                                   \
  return -1;

/* Fixes for Mac OS X */
#ifndef SOCK_CLOEXEC
# define SOCK_CLOEXEC O_CLOEXEC
#endif
#ifndef SOCK_NONBLOCK
# define SOCK_NONBLOCK O_NONBLOCK
#endif
/* End of fixes for Mac OS X */

#ifdef HAVE_LIBVIRT

#ifndef HAVE_XMLBUFFERDETACH
/* Added in libxml2 2.8.0.  This is mostly a copy of the function from
 * upstream libxml2, which is under a more permissive license.
 */
static xmlChar *
xmlBufferDetach (xmlBufferPtr buf)
{
  xmlChar *ret;

  if (buf == NULL)
    return NULL;
  if (buf->alloc == XML_BUFFER_ALLOC_IMMUTABLE)
    return NULL;

  ret = buf->content;
  buf->content = NULL;
  buf->size = 0;
  buf->use = 0;

  return ret;
}
#endif

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_VIRSECRETFREE __attribute__((cleanup(cleanup_virSecretFree)))

static void
cleanup_virSecretFree (void *ptr)
{
  virSecretPtr secret_obj = * (virSecretPtr *) ptr;
  if (secret_obj)
    virSecretFree (secret_obj);
}

#else /* !HAVE_ATTRIBUTE_CLEANUP */
#define CLEANUP_VIRSECRETFREE
#endif

/* List used to store a mapping of secret to libvirt secret UUID. */
struct secret {
  char *secret;
  char uuid[VIR_UUID_STRING_BUFLEN];
};

#define DOMAIN_NAME_LEN (8+16+1) /* "guestfs-" + random + \0 */

/* Per-handle data. */
struct backend_libvirt_data {
  virConnectPtr conn;           /* libvirt connection */
  virDomainPtr dom;             /* libvirt domain */
  char *selinux_label;
  char *selinux_imagelabel;
  bool selinux_norelabel_disks;
  char name[DOMAIN_NAME_LEN];   /* random name */
  bool is_kvm;                  /* false = qemu, true = kvm (from capabilities)*/
  struct version libvirt_version; /* libvirt version */
  struct version qemu_version;  /* qemu version (from libvirt) */
  struct secret *secrets;       /* list of secrets */
  size_t nr_secrets;
  char *uefi_code;		/* UEFI (firmware) code and variables. */
  char *uefi_vars;
  char *default_qemu;           /* default qemu (from domcapabilities) */
  char **firmware_autoselect;   /* supported firmwares (from domcapabilities);
                                 * NULL means "not supported", otherwise it
                                 * contains a list with supported values for
                                 * <os firmware='...'>
                                 */
  const char *firmware;         /* firmware to set in autoselection mode;
                                 * points to one of the elements in
                                 * "firmware_autoselect"
                                 */
  char guestfsd_path[UNIX_PATH_MAX]; /* paths to sockets */
  char console_path[UNIX_PATH_MAX];
};

/* Parameters passed to construct_libvirt_xml and subfunctions.  We
 * keep them all in a structure for convenience!
 */
struct libvirt_xml_params {
  struct backend_libvirt_data *data;
  char *kernel;                 /* paths to kernel, initrd and appliance */
  char *initrd;
  char *appliance;
  char *appliance_overlay;      /* path to qcow2 overlay backed by appliance */
  char appliance_dev[64];       /* appliance device name */
  size_t appliance_index;       /* index of appliance */
  bool enable_svirt;            /* false if we decided to disable sVirt */
  bool current_proc_is_root;    /* true = euid is root */
};

static int parse_capabilities (guestfs_h *g, const char *capabilities_xml, struct backend_libvirt_data *data);
static int parse_domcapabilities (guestfs_h *g, const char *domcapabilities_xml, struct backend_libvirt_data *data);
static int add_secret (guestfs_h *g, virConnectPtr conn, struct backend_libvirt_data *data, const struct drive *drv);
static int find_secret (guestfs_h *g, const struct backend_libvirt_data *data, const struct drive *drv, const char **type, const char **uuid);
static int have_secret (guestfs_h *g, const struct backend_libvirt_data *data, const struct drive *drv);
static xmlChar *construct_libvirt_xml (guestfs_h *g, const struct libvirt_xml_params *params);
static void debug_appliance_permissions (guestfs_h *g);
static void debug_socket_permissions (guestfs_h *g);
static void libvirt_error (guestfs_h *g, const char *fs, ...) __attribute__((format (printf,2,3)));
static void libvirt_debug (guestfs_h *g, const char *fs, ...) __attribute__((format (printf,2,3)));
static int is_custom_hv (guestfs_h *g, struct backend_libvirt_data *data);
static int is_blk (const char *path);
static void ignore_errors (void *ignore, virErrorPtr ignore2);
static void set_socket_create_context (guestfs_h *g);
static void clear_socket_create_context (guestfs_h *g);

#if HAVE_LIBSELINUX
static void selinux_warning (guestfs_h *g, const char *func, const char *selinux_op, const char *data);
#endif

/**
 * Return C<drv-E<gt>src.format>, but if it is C<NULL>, autodetect the
 * format.
 *
 * libvirt has disabled the feature of detecting the disk format,
 * unless the administrator sets C<allow_disk_format_probing=1> in
 * F</etc/libvirt/qemu.conf>.  There is no way to detect if this
 * option is set, so we have to do format detection here using
 * C<qemu-img> and pass that to libvirt.
 *
 * This can still be a security issue, so in most cases it is
 * recommended the users pass the format to libguestfs which will
 * faithfully pass that straight through to libvirt without doing
 * autodetection.
 *
 * Caller must free the returned string.  On error this function sets
 * the error in the handle and returns C<NULL>.
 */
static char *
get_source_format_or_autodetect (guestfs_h *g, struct drive *drv)
{
  if (drv->src.format)
    return safe_strdup (g, drv->src.format);

  if (drv->src.protocol == drive_protocol_file) {
    char *format;

    format = guestfs_disk_format (g, drv->src.u.path);
    if (!format)
      return NULL;

    if (STREQ (format, "unknown")) {
      error (g, _("could not auto-detect the format.\n"
                  "If the format is known, pass the format to libguestfs, eg. using the\n"
                  "‘--format’ option, or via the optional ‘format’ argument to ‘add-drive’."));
      free (format);
      return NULL;
    }

    return format;
  }

  /* Non-file protocol. */
  error (g, _("could not auto-detect the format when using a non-file protocol.\n"
              "If the format is known, pass the format to libguestfs, eg. using the\n"
              "‘--format’ option, or via the optional ‘format’ argument to ‘add-drive’."));
  return NULL;
}

/**
 * Create a qcow2 format overlay, with the given C<backing_drive>
 * (file).  The C<format> parameter is the backing file format.
 * The C<format> parameter can be NULL, in this case the backing
 * format will be determined automatically.  This is used to create
 * the appliance overlay, and also for read-only drives.
 */
static char *
make_qcow2_overlay (guestfs_h *g, const char *backing_drive,
                    const char *format)
{
  char *overlay;
  struct guestfs_disk_create_argv optargs;

  overlay = guestfs_int_make_temp_path (g, "overlay", "qcow2");
  if (!overlay)
    return NULL;

  optargs.bitmask = GUESTFS_DISK_CREATE_BACKINGFILE_BITMASK;
  optargs.backingfile = backing_drive;
  if (format) {
    optargs.bitmask |= GUESTFS_DISK_CREATE_BACKINGFORMAT_BITMASK;
    optargs.backingformat = format;
  }

  if (guestfs_disk_create_argv (g, overlay, "qcow2", -1, &optargs) == -1) {
    free (overlay);
    return NULL;
  }

  return overlay;
}

static char *
create_cow_overlay_libvirt (guestfs_h *g, void *datav, struct drive *drv)
{
#if HAVE_LIBSELINUX
  struct backend_libvirt_data *data = datav;
#endif
  CLEANUP_FREE char *backing_drive = NULL;
  CLEANUP_FREE char *format = NULL;
  char *overlay;

  backing_drive = guestfs_int_drive_source_qemu_param (g, &drv->src);
  if (!backing_drive)
    return NULL;

  format = get_source_format_or_autodetect (g, drv);
  if (!format)
    return NULL;

  overlay = make_qcow2_overlay (g, backing_drive, format);
  if (!overlay)
    return NULL;

#if HAVE_LIBSELINUX
  /* Since this function is called before launch, the field won't be
   * initialized correctly, so we have to initialize it here.
   */
  guestfs_push_error_handler (g, NULL, NULL);
  free (data->selinux_imagelabel);
  data->selinux_imagelabel =
    guestfs_get_backend_setting (g, "internal_libvirt_imagelabel");
  guestfs_pop_error_handler (g);

  if (data->selinux_imagelabel) {
    debug (g, "setting SELinux label on %s to %s",
           overlay, data->selinux_imagelabel);
    if (setfilecon (overlay, data->selinux_imagelabel) == -1)
      selinux_warning (g, __func__, "setfilecon", overlay);
  }
#endif

  /* Caller sets g->overlay in the handle to this, and then manages
   * the memory.
   */
  return overlay;
}

static int
launch_libvirt (guestfs_h *g, void *datav, const char *libvirt_uri)
{
  struct backend_libvirt_data *data = datav;
  int daemon_accept_sock = -1, console_sock = -1;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  CLEANUP_FREE char *capabilities_xml = NULL;
  struct libvirt_xml_params params = {
    .data = data,
    .kernel = NULL,
    .initrd = NULL,
    .appliance = NULL,
    .appliance_overlay = NULL,
  };
  CLEANUP_FREE xmlChar *xml = NULL;
  struct sockaddr_un addr;
  struct drive *drv;
  size_t i;
  int r;
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;
  unsigned long version_number;
  int uefi_flags;
  CLEANUP_FREE char *domcapabilities_xml = NULL;

  params.current_proc_is_root = geteuid () == 0;

  /* XXX: It should be possible to make this work. */
  if (g->direct_mode) {
    error (g, _("direct mode flag is not supported yet for libvirt backend"));
    return -1;
  }

  virGetVersion (&version_number, NULL, NULL);
  guestfs_int_version_from_libvirt (&data->libvirt_version, version_number);
  debug (g, "libvirt version = %lu (%d.%d.%d)",
         version_number,
         data->libvirt_version.v_major,
         data->libvirt_version.v_minor,
         data->libvirt_version.v_micro);
  guestfs_int_launch_send_progress (g, 0);

  /* Create a random name for the guest. */
  memcpy (data->name, "guestfs-", 8);
  const size_t random_name_len =
    DOMAIN_NAME_LEN - 8 /* "guestfs-" */ - 1 /* \0 */;
  if (guestfs_int_random_string (&data->name[8], random_name_len) == -1) {
    perrorf (g, "guestfs_int_random_string");
    return -1;
  }
  debug (g, "guest random name = %s", data->name);

  debug (g, "connect to libvirt");

  /* Decode the URI string. */
  if (!libvirt_uri) {           /* "libvirt" */
    if (!params.current_proc_is_root)
      libvirt_uri = "qemu:///session";
    else
      libvirt_uri = "qemu:///system";
  } else if (STREQ (libvirt_uri, "null")) { /* libvirt:null */
    libvirt_uri = NULL;
  } /* else nothing */

  /* Connect to libvirt, get capabilities. */
  conn = guestfs_int_open_libvirt_connection (g, libvirt_uri, 0);
  if (!conn) {
    libvirt_error (g, _("could not connect to libvirt (URI = %s)"),
                   libvirt_uri ? : "NULL");
    goto cleanup;
  }

  /* Suppress default behaviour of printing errors to stderr.  Note
   * you can't set this to NULL to ignore errors; setting it to NULL
   * restores the default error handler ...
   */
  virConnSetErrorFunc (conn, NULL, ignore_errors);

  /* Get hypervisor (hopefully qemu) version. */
  if (virConnectGetVersion (conn, &version_number) == 0) {
    guestfs_int_version_from_libvirt (&data->qemu_version, version_number);
    debug (g, "qemu version (reported by libvirt) = %lu (%d.%d.%d)",
           version_number,
           data->qemu_version.v_major,
           data->qemu_version.v_minor,
           data->qemu_version.v_micro);
  }
  else {
    libvirt_debug (g, "unable to read qemu version from libvirt");
    version_init_null (&data->qemu_version);
  }

  debug (g, "get libvirt capabilities");

  capabilities_xml = virConnectGetCapabilities (conn);
  if (!capabilities_xml) {
    libvirt_error (g, _("could not get libvirt capabilities"));
    goto cleanup;
  }

  /* Parse capabilities XML.  This fills in various fields in 'params'
   * struct, and can also fail if we detect that the hypervisor cannot
   * run qemu guests (RHBZ#886915).
   */
  debug (g, "parsing capabilities XML");

  if (parse_capabilities (g, capabilities_xml, data) == -1)
    goto cleanup;

  domcapabilities_xml = virConnectGetDomainCapabilities (conn, NULL, NULL,
#ifdef MACHINE_TYPE
                                                         MACHINE_TYPE,
#else
                                                         NULL,
#endif
                                                         NULL, 0);
  if (!domcapabilities_xml) {
    libvirt_error (g, _("could not get libvirt domain capabilities"));
    goto cleanup;
  }

  /* Parse domcapabilities XML.
   */
  debug (g, "parsing domcapabilities XML");

  if (parse_domcapabilities (g, domcapabilities_xml, data) == -1)
    goto cleanup;

  /* UEFI code and variables, on architectures where that is required. */
  if (guestfs_int_get_uefi (g, data->firmware_autoselect, &data->firmware,
                            &data->uefi_code, &data->uefi_vars,
                            &uefi_flags) == -1)
    goto cleanup;
  if (uefi_flags & UEFI_FLAG_SECURE_BOOT_REQUIRED) {
    /* Implementing this requires changes to the libvirt XML.  See
     * RHBZ#1367615 for details.  As the guestfs_int_get_uefi function
     * is only implemented for aarch64, and UEFI secure boot is some
     * way off on aarch64 (2017/2018), we only need to worry about
     * this later.
     */
    error (g, "internal error: libvirt backend "
           "does not implement UEFI secure boot, "
           "see comments in the code");
    goto cleanup;
  }

  /* Misc backend settings. */
  guestfs_push_error_handler (g, NULL, NULL);
  free (data->selinux_label);
  data->selinux_label =
    guestfs_get_backend_setting (g, "internal_libvirt_label");
  free (data->selinux_imagelabel);
  data->selinux_imagelabel =
    guestfs_get_backend_setting (g, "internal_libvirt_imagelabel");
  data->selinux_norelabel_disks =
    guestfs_int_get_backend_setting_bool (g, "internal_libvirt_norelabel_disks");
  guestfs_pop_error_handler (g);

  /* Locate and/or build the appliance. */
  debug (g, "build appliance");

  if (guestfs_int_build_appliance (g, &params.kernel, &params.initrd,
                                   &params.appliance) == -1)
    goto cleanup;

  guestfs_int_launch_send_progress (g, 3);

  /* Note that appliance can be NULL if using the old-style appliance. */
  if (params.appliance) {
#ifndef APPLIANCE_FORMAT_AUTO
    params.appliance_overlay = make_qcow2_overlay (g, params.appliance, "raw");
#else
    params.appliance_overlay = make_qcow2_overlay (g, params.appliance, NULL);
#endif
    if (!params.appliance_overlay)
      goto cleanup;
  }

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  if (guestfs_int_create_socketname (g, "guestfsd.sock",
                                     &data->guestfsd_path) == -1)
    goto cleanup;

  set_socket_create_context (g);

  daemon_accept_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (daemon_accept_sock == -1) {
    perrorf (g, "socket");
    goto cleanup;
  }

  addr.sun_family = AF_UNIX;
  memcpy (addr.sun_path, data->guestfsd_path, UNIX_PATH_MAX);

  if (bind (daemon_accept_sock, (struct sockaddr *) &addr,
            sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (listen (daemon_accept_sock, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup;
  }

  /* For the serial console. */
  if (guestfs_int_create_socketname (g, "console.sock",
                                     &data->console_path) == -1)
    goto cleanup;

  console_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (console_sock == -1) {
    perrorf (g, "socket");
    goto cleanup;
  }

  addr.sun_family = AF_UNIX;
  memcpy (addr.sun_path, data->console_path, UNIX_PATH_MAX);

  if (bind (console_sock, (struct sockaddr *) &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (listen (console_sock, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup;
  }

  clear_socket_create_context (g);

  /* libvirt, if running as root, will run the qemu process as
   * qemu.qemu, which means it won't be able to access the socket.
   * There are roughly three things that get in the way:
   *
   * (1) Permissions of the socket.
   *
   * (2) Permissions of the parent directory(-ies).  Remember this if
   *     $TMPDIR is located in your home directory.
   *
   * (3) SELinux/sVirt will prevent access.  libvirt ought to label
   *     the socket.
   *
   * Note that the 'current_proc_is_root' flag here just means that we
   * are root.  It's also possible for non-root user to try to use the
   * system libvirtd by specifying a qemu:///system URI (RHBZ#913774)
   * but there's no sane way to test for that.
   */
  if (params.current_proc_is_root) {
    /* Current process is root, so try to create sockets that are
     * owned by root.qemu with mode 0660 and hence accessible to qemu.
     */
    struct group *grp;

    if (chmod (data->guestfsd_path, 0660) == -1) {
      perrorf (g, "chmod: %s", data->guestfsd_path);
      goto cleanup;
    }

    if (chmod (data->console_path, 0660) == -1) {
      perrorf (g, "chmod: %s", data->console_path);
      goto cleanup;
    }

    grp = getgrnam ("qemu");
    if (grp != NULL) {
      if (chown (data->guestfsd_path, 0, grp->gr_gid) == -1) {
        perrorf (g, "chown: %s", data->guestfsd_path);
        goto cleanup;
      }
      if (chown (data->console_path, 0, grp->gr_gid) == -1) {
        perrorf (g, "chown: %s", data->console_path);
        goto cleanup;
      }
    } else
      debug (g, "cannot find group 'qemu'");
  }

  /* Store any secrets in libvirtd, keeping a mapping from the secret
   * to its UUID.
   */
  ITER_DRIVES (g, i, drv) {
    if (add_secret (g, conn, data, drv) == -1)
      goto cleanup;
  }

  /* Construct the libvirt XML. */
  debug (g, "create libvirt XML");

  params.appliance_index = g->nr_drives;
  strcpy (params.appliance_dev, "/dev/sd");
  guestfs_int_drive_name (params.appliance_index, &params.appliance_dev[7]);
  params.enable_svirt = ! is_custom_hv (g, data);

  xml = construct_libvirt_xml (g, &params);
  if (!xml)
    goto cleanup;

  /* Debug permissions and SELinux contexts on appliance and sockets. */
  if (g->verbose) {
    debug_appliance_permissions (g);
    debug_socket_permissions (g);
  }

  /* Launch the libvirt guest. */
  debug (g, "launch libvirt guest");

  dom = virDomainCreateXML (conn, (char *) xml, VIR_DOMAIN_START_AUTODESTROY);
  if (!dom) {
    libvirt_error (g, _(
                        "could not create appliance through libvirt.\n"
                        "\n"
                        "Try running qemu directly without libvirt using this environment variable:\n"
                        "export LIBGUESTFS_BACKEND=direct\n"
                        "\n"
                        "Original error from libvirt"));
    goto cleanup;
  }

  g->state = LAUNCHING;

  /* Wait for console socket to be opened (by qemu). */
  r = accept4 (console_sock, NULL, NULL, SOCK_NONBLOCK|SOCK_CLOEXEC);
  if (r == -1) {
    perrorf (g, "accept");
    goto cleanup;
  }
  if (close (console_sock) == -1) {
    perrorf (g, "close: console socket");
    console_sock = -1;
    close (r);
    goto cleanup;
  }
  console_sock = r;         /* This is the accepted console socket. */

  /* Wait for libvirt domain to start and to connect back to us via
   * virtio-serial and send the GUESTFS_LAUNCH_FLAG message.
   */
  g->conn =
    guestfs_int_new_conn_socket_listening (g, daemon_accept_sock, console_sock);
  if (!g->conn)
    goto cleanup;

  /* g->conn now owns these sockets. */
  daemon_accept_sock = console_sock = -1;

  r = g->conn->ops->accept_connection (g, g->conn);
  if (r == -1)
    goto cleanup;
  if (r == 0) {
    guestfs_int_launch_failed_error (g);
    goto cleanup;
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
    goto cleanup;
  }

  if (size != GUESTFS_LAUNCH_FLAG) {
    guestfs_int_launch_failed_error (g);
    goto cleanup;
  }

  debug (g, "appliance is up");

  /* This is possible in some really strange situations, such as
   * guestfsd starts up OK but then qemu immediately exits.  Check for
   * it because the caller is probably expecting to be able to send
   * commands after this function returns.
   */
  if (g->state != READY) {
    error (g, _("qemu launched and contacted daemon, but state != READY"));
    goto cleanup;
  }

  if (params.appliance)
    guestfs_int_add_dummy_appliance_drive (g);

  guestfs_int_launch_send_progress (g, 12);

  data->conn = conn;
  data->dom = dom;

  free (params.kernel);
  free (params.initrd);
  free (params.appliance);
  free (params.appliance_overlay);

  return 0;

 cleanup:
  clear_socket_create_context (g);

  if (console_sock >= 0)
    close (console_sock);
  if (daemon_accept_sock >= 0)
    close (daemon_accept_sock);
  if (g->conn) {
    g->conn->ops->free_connection (g, g->conn);
    g->conn = NULL;
  }

  if (dom) {
    virDomainDestroy (dom);
    virDomainFree (dom);
  }
  if (conn)
    virConnectClose (conn);

  free (params.kernel);
  free (params.initrd);
  free (params.appliance);
  free (params.appliance_overlay);

  g->state = CONFIG;

  return -1;
}

static int
parse_capabilities (guestfs_h *g, const char *capabilities_xml,
                    struct backend_libvirt_data *data)
{
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  size_t i;
  xmlNodeSetPtr nodes;
  xmlAttrPtr attr;
  size_t seen_qemu, seen_kvm;
  int force_tcg;
  int force_kvm;

  doc = xmlReadMemory (capabilities_xml, strlen (capabilities_xml),
                       NULL, NULL, XML_PARSE_NONET);
  if (doc == NULL) {
    error (g, _("unable to parse capabilities XML returned by libvirt"));
    return -1;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    return -1;
  }

  /* This gives us a set of all the supported domain types.
   * XXX It ignores architecture, but let's not worry about that.
   */
#define XPATH_EXPR "/capabilities/guest/arch/domain/@type"
  xpathObj = xmlXPathEvalExpression (BAD_CAST XPATH_EXPR, xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression: %s"), XPATH_EXPR);
    return -1;
  }
#undef XPATH_EXPR

  nodes = xpathObj->nodesetval;
  seen_qemu = seen_kvm = 0;

  if (nodes != NULL) {
    for (i = 0; i < (size_t) nodes->nodeNr; ++i) {
      CLEANUP_FREE char *type = NULL;

      if (seen_qemu && seen_kvm)
        break;

      assert (nodes->nodeTab[i]);
      assert (nodes->nodeTab[i]->type == XML_ATTRIBUTE_NODE);
      attr = (xmlAttrPtr) nodes->nodeTab[i];
      type = (char *) xmlNodeListGetString (doc, attr->children, 1);

      if (STREQ (type, "qemu"))
        seen_qemu++;
      else if (STREQ (type, "kvm"))
        seen_kvm++;
    }
  }

  force_kvm = guestfs_int_get_backend_setting_bool (g, "force_kvm");
  if (force_kvm == -1)
    return -1;

  /* This was RHBZ#886915: in that case the default libvirt URI
   * pointed to a Xen hypervisor, and so could not create the
   * appliance VM.
   */
  if ((!seen_qemu || force_kvm) && !seen_kvm) {
    CLEANUP_FREE char *backend = guestfs_get_backend (g);

    error (g,
           _("libvirt hypervisor doesn’t support qemu or KVM,\n"
             "so we cannot create the libguestfs appliance.\n"
             "The current backend is ‘%s’.\n"
             "Check that the PATH environment variable is set and contains\n"
             "the path to the qemu (‘qemu-system-*’) or KVM (‘qemu-kvm’, ‘kvm’ etc).\n"
             "Or: try setting:\n"
             "  export LIBGUESTFS_BACKEND=libvirt:qemu:///session\n"
             "Or: if you want to have libguestfs run qemu directly, try:\n"
             "  export LIBGUESTFS_BACKEND=direct\n"
             "For further help, read the guestfs(3) man page and libguestfs FAQ."),
           backend);
    return -1;
  }

  force_tcg = guestfs_int_get_backend_setting_bool (g, "force_tcg");
  if (force_tcg == -1)
    return -1;

  if (force_kvm && force_tcg) {
    error (g, "Both force_kvm and force_tcg backend settings supplied.");
    return -1;
  }

  /* if force_kvm then seen_kvm */
  assert (!force_kvm || seen_kvm);

  if (!force_tcg)
    data->is_kvm = seen_kvm;
  else
    data->is_kvm = 0;

  return 0;
}

static int
parse_domcapabilities (guestfs_h *g, const char *domcapabilities_xml,
                       struct backend_libvirt_data *data)
{
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  xmlNodeSetPtr nodes;
  size_t i;

  doc = xmlReadMemory (domcapabilities_xml, strlen (domcapabilities_xml),
                       NULL, NULL, XML_PARSE_NONET);
  if (doc == NULL) {
    error (g, _("unable to parse domain capabilities XML returned by libvirt"));
    return -1;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    return -1;
  }

  /* This gives us the default QEMU. */
#define XPATH_EXPR "string(/domainCapabilities/path/text())"
  xpathObj = xmlXPathEvalExpression (BAD_CAST XPATH_EXPR, xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression: %s"), XPATH_EXPR);
    return -1;
  }
#undef XPATH_EXPR

  assert (xpathObj->type == XPATH_STRING);
  data->default_qemu = safe_strdup (g, (char *) xpathObj->stringval);

  /*
   * This gives us whether the firmware autoselection is supported,
   * and which values are allowed.
   */
#define XPATH_EXPR "/domainCapabilities/os/enum[@name='firmware']/value"
  xmlXPathFreeObject (xpathObj);
  xpathObj = xmlXPathEvalExpression (BAD_CAST XPATH_EXPR, xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression: %s"), XPATH_EXPR);
    return -1;
  }
#undef XPATH_EXPR

  assert (xpathObj->type == XPATH_NODESET);
  nodes = xpathObj->nodesetval;
  if (nodes != NULL) {
    data->firmware_autoselect = safe_calloc (g, nodes->nodeNr + 1, sizeof (char *));
    for (i = 0; i < (size_t) nodes->nodeNr; ++i)
      data->firmware_autoselect[i] = (char *) xmlNodeGetContent(nodes->nodeTab[i]);
  }

  return 0;
}

static int
is_custom_hv (guestfs_h *g, struct backend_libvirt_data *data)
{
  if (g->hv && STRNEQ (g->hv, data->default_qemu))
    return 1;
#ifdef QEMU
  if (STRNEQ (data->default_qemu, QEMU))
    return 1;
#endif
  return 0;
}

#if HAVE_LIBSELINUX

/* Set sVirt (SELinux) socket create context.  For details see:
 * https://bugzilla.redhat.com/show_bug.cgi?id=853393#c14
 */

#define SOCKET_CONTEXT "svirt_socket_t"

static void
set_socket_create_context (guestfs_h *g)
{
  char *scon;
  context_t con;

  if (getcon (&scon) == -1) {
    selinux_warning (g, __func__, "getcon", NULL);
    return;
  }

  con = context_new (scon);
  if (!con) {
    selinux_warning (g, __func__, "context_new", scon);
    goto out1;
  }

  if (context_type_set (con, SOCKET_CONTEXT) == -1) {
    selinux_warning (g, __func__, "context_type_set", scon);
    goto out2;
  }

  /* Note that setsockcreatecon sets the per-thread socket creation
   * context (/proc/self/task/<tid>/attr/sockcreate) so this is
   * thread-safe.
   */
  if (setsockcreatecon (context_str (con)) == -1) {
    selinux_warning (g, __func__, "setsockcreatecon", context_str (con));
    goto out2;
  }

 out2:
  context_free (con);
 out1:
  freecon (scon);
}

static void
clear_socket_create_context (guestfs_h *g)
{
  if (setsockcreatecon (NULL) == -1)
    selinux_warning (g, __func__, "setsockcreatecon", "NULL");
}

#else /* !HAVE_LIBSELINUX */

static void
set_socket_create_context (guestfs_h *g)
{
  /* nothing */
}

static void
clear_socket_create_context (guestfs_h *g)
{
  /* nothing */
}

#endif /* !HAVE_LIBSELINUX */

static void
debug_permissions_cb (guestfs_h *g, void *data, const char *line, size_t len)
{
  debug (g, "%s", line);
}

static void
debug_appliance_permissions (guestfs_h *g)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  CLEANUP_FREE char *cachedir = guestfs_get_cachedir (g);
  CLEANUP_FREE char *appliance = NULL;

  appliance = safe_asprintf (g, "%s/.guestfs-%ju",
                             cachedir, (uintmax_t) geteuid ());

  guestfs_int_cmd_add_arg (cmd, "ls");
  guestfs_int_cmd_add_arg (cmd, "-a");
  guestfs_int_cmd_add_arg (cmd, "-l");
  guestfs_int_cmd_add_arg (cmd, "-R");
  guestfs_int_cmd_add_arg (cmd, "-Z");
  guestfs_int_cmd_add_arg (cmd, appliance);
  guestfs_int_cmd_set_stdout_callback (cmd, debug_permissions_cb, NULL, 0);
  guestfs_int_cmd_run (cmd);
}

static void
debug_socket_permissions (guestfs_h *g)
{
  if (g->tmpdir) {
    CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);

    guestfs_int_cmd_add_arg (cmd, "ls");
    guestfs_int_cmd_add_arg (cmd, "-a");
    guestfs_int_cmd_add_arg (cmd, "-l");
    guestfs_int_cmd_add_arg (cmd, "-Z");
    guestfs_int_cmd_add_arg (cmd, g->sockdir);
    guestfs_int_cmd_set_stdout_callback (cmd, debug_permissions_cb, NULL, 0);
    guestfs_int_cmd_run (cmd);
  }
}

static int construct_libvirt_xml_domain (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_name (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_cpu (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_boot (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_seclabel (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_lifecycle (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_devices (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_qemu_cmdline (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);
static int construct_libvirt_xml_disk (guestfs_h *g, const struct backend_libvirt_data *data, xmlTextWriterPtr xo, struct drive *drv, size_t drv_index);
static int construct_libvirt_xml_disk_target (guestfs_h *g, xmlTextWriterPtr xo, size_t drv_index);
static int construct_libvirt_xml_disk_driver_qemu (guestfs_h *g, const struct backend_libvirt_data *data, struct drive *drv, xmlTextWriterPtr xo, const char *format, const char *cachemode, enum discard discard, bool copyonread);
static int construct_libvirt_xml_disk_address (guestfs_h *g, xmlTextWriterPtr xo, size_t drv_index);
static int construct_libvirt_xml_disk_blockio (guestfs_h *g, xmlTextWriterPtr xo, int blocksize);
static int construct_libvirt_xml_disk_source_hosts (guestfs_h *g, xmlTextWriterPtr xo, const struct drive_source *src);
static int construct_libvirt_xml_disk_source_seclabel (guestfs_h *g, const struct backend_libvirt_data *data, xmlTextWriterPtr xo);
static int construct_libvirt_xml_appliance (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);

static xmlChar *
construct_libvirt_xml (guestfs_h *g, const struct libvirt_xml_params *params)
{
  xmlChar *ret = NULL;
  CLEANUP_XMLBUFFERFREE xmlBufferPtr xb = NULL;
  xmlOutputBufferPtr ob;
  CLEANUP_XMLFREETEXTWRITER xmlTextWriterPtr xo = NULL;

  xb = xmlBufferCreate ();
  if (xb == NULL) {
    perrorf (g, "xmlBufferCreate");
    return NULL;
  }
  ob = xmlOutputBufferCreateBuffer (xb, NULL);
  if (ob == NULL) {
    perrorf (g, "xmlOutputBufferCreateBuffer");
    return NULL;
  }
  xo = xmlNewTextWriter (ob);
  if (xo == NULL) {
    perrorf (g, "xmlNewTextWriter");
    return NULL;
  }

  if (xmlTextWriterSetIndent (xo, 1) == -1 ||
      xmlTextWriterSetIndentString (xo, BAD_CAST "  ") == -1) {
    perrorf (g, "could not set XML indent");
    return NULL;
  }
  if (xmlTextWriterStartDocument (xo, NULL, NULL, NULL) == -1) {
    perrorf (g, "xmlTextWriterStartDocument");
    return NULL;
  }

  if (construct_libvirt_xml_domain (g, params, xo) == -1)
    return NULL;

  if (xmlTextWriterEndDocument (xo) == -1) {
    perrorf (g, "xmlTextWriterEndDocument");
    return NULL;
  }
  ret = xmlBufferDetach (xb); /* caller frees ret */
  if (ret == NULL) {
    perrorf (g, "xmlBufferDetach");
    return NULL;
  }

  debug (g, "libvirt XML:\n%s", ret);

  return ret;
}

static int
construct_libvirt_xml_domain (guestfs_h *g,
                              const struct libvirt_xml_params *params,
                              xmlTextWriterPtr xo)
{
  start_element ("domain") {
    attribute ("type", params->data->is_kvm ? "kvm" : "qemu");
    attribute_ns ("xmlns", "qemu", NULL,
                  "http://libvirt.org/schemas/domain/qemu/1.0");

    if (construct_libvirt_xml_name (g, params, xo) == -1)
      return -1;
    if (construct_libvirt_xml_cpu (g, params, xo) == -1)
      return -1;
    if (construct_libvirt_xml_boot (g, params, xo) == -1)
      return -1;
    if (construct_libvirt_xml_seclabel (g, params, xo) == -1)
      return -1;
    if (construct_libvirt_xml_lifecycle (g, params, xo) == -1)
      return -1;
    if (construct_libvirt_xml_devices (g, params, xo) == -1)
      return -1;
    if (construct_libvirt_xml_qemu_cmdline (g, params, xo) == -1)
      return -1;

  } end_element ();

  return 0;
}

static int
construct_libvirt_xml_name (guestfs_h *g,
                            const struct libvirt_xml_params *params,
                            xmlTextWriterPtr xo)
{
  single_element ("name", params->data->name);
  return 0;
}

/* CPU and memory features. */
static int
construct_libvirt_xml_cpu (guestfs_h *g,
                           const struct libvirt_xml_params *params,
                           xmlTextWriterPtr xo)
{
  const char *cpu_model;

  start_element ("memory") {
    attribute ("unit", "MiB");
    string_format ("%d", g->memsize);
  } end_element ();

  start_element ("currentMemory") {
    attribute ("unit", "MiB");
    string_format ("%d", g->memsize);
  } end_element ();

  cpu_model = guestfs_int_get_cpu_model (params->data->is_kvm);
  if (cpu_model) {
    start_element ("cpu") {
      if (STREQ (cpu_model, "host")) {
        attribute ("mode", "host-passthrough");
        start_element ("model") {
          attribute ("fallback", "allow");
        } end_element ();
      }
      else if (STREQ (cpu_model, "max")) {
        /* https://bugzilla.redhat.com/show_bug.cgi?id=1935572#c11 */
        attribute ("mode", "maximum");
#if defined(__x86_64__)
        /* Temporary workaround for RHBZ#2082806 */
        start_element ("feature") {
          attribute ("policy", "disable");
          attribute ("name", "la57");
        } end_element ();
#endif
      }
      else
        single_element ("model", cpu_model);
    } end_element ();
  }

  single_element_format ("vcpu", "%d", g->smp);

  start_element ("clock") {
    attribute ("offset", "utc");

    /* These are recommended settings, see RHBZ#1053847. */
    start_element ("timer") {
      attribute ("name", "rtc");
      attribute ("tickpolicy", "catchup");
    } end_element ();
    start_element ("timer") {
      attribute ("name", "pit");
      attribute ("tickpolicy", "delay");
    } end_element ();

    /* libvirt has a bug (RHBZ#1066145) where it adds the -no-hpet
     * flag on ARM & ppc64 (and possibly any architecture).
     * Since hpet is specific to x86 & x86_64 anyway, just add it only
     * for those architectures.
     */
#if defined(__i386__) || defined(__x86_64__)
    start_element ("timer") {
      attribute ("name", "hpet");
      attribute ("present", "no");
    } end_element ();
#endif
  } end_element ();

  return 0;
}

/* Boot parameters. */
static int
construct_libvirt_xml_boot (guestfs_h *g,
                            const struct libvirt_xml_params *params,
                            xmlTextWriterPtr xo)
{
  CLEANUP_FREE char *cmdline = NULL;
  int flags;

  /* Linux kernel command line. */
  flags = 0;
  if (!params->data->is_kvm)
    flags |= APPLIANCE_COMMAND_LINE_IS_TCG;
  cmdline = guestfs_int_appliance_command_line (g, params->appliance, flags);

  start_element ("os") {
    if (params->data->firmware)
      attribute ("firmware", params->data->firmware);

    start_element ("type") {
#ifdef MACHINE_TYPE
      attribute ("machine", MACHINE_TYPE);
#endif
      string ("hvm");
    } end_element ();

    if (params->data->uefi_code) {
      start_element ("loader") {
        attribute ("readonly", "yes");
        attribute ("type", "pflash");
        string (params->data->uefi_code);
      } end_element ();

      if (params->data->uefi_vars)
        single_element ("nvram", params->data->uefi_vars);
    }

    single_element ("kernel", params->kernel);
    single_element ("initrd", params->initrd);
    single_element ("cmdline", cmdline);

#if defined(__i386__) || defined(__x86_64__)
    if (g->verbose) {
      start_element ("bios") {
        attribute ("useserial", "yes");
      } end_element ();
    }
#endif

  } end_element ();

  return 0;
}

static int
construct_libvirt_xml_seclabel (guestfs_h *g,
                                const struct libvirt_xml_params *params,
                                xmlTextWriterPtr xo)
{
  if (!params->enable_svirt) {
    /* This disables SELinux/sVirt confinement. */
    start_element ("seclabel") {
      attribute ("type", "none");
    } end_element ();
  }
  else if (params->data->selinux_label && params->data->selinux_imagelabel) {
    /* Enable sVirt and pass a custom <seclabel/> inherited from the
     * original libvirt domain (when guestfs_add_domain was called).
     * https://bugzilla.redhat.com/show_bug.cgi?id=912499#c7
     */
    start_element ("seclabel") {
      attribute ("type", "static");
      attribute ("model", "selinux");
      attribute ("relabel", "yes");
      single_element ("label", params->data->selinux_label);
      single_element ("imagelabel", params->data->selinux_imagelabel);
    } end_element ();
  }

  return 0;
}

/* qemu -no-reboot */
static int
construct_libvirt_xml_lifecycle (guestfs_h *g,
                                 const struct libvirt_xml_params *params,
                                 xmlTextWriterPtr xo)
{
  single_element ("on_reboot", "destroy");
  return 0;
}

/* Devices. */
static int
construct_libvirt_xml_devices (guestfs_h *g,
                               const struct libvirt_xml_params *params,
                               xmlTextWriterPtr xo)
{
  struct drive *drv;
  size_t i;

  start_element ("devices") {

    /* Path to hypervisor.  Only write this if the user has changed the
     * default, otherwise allow libvirt to choose the best one.
     */
    if (is_custom_hv (g, params->data))
      single_element ("emulator", g->hv);
#if defined(__arm__)
    /* Hopefully temporary hack to make ARM work (otherwise libvirt
     * chooses to run /usr/bin/qemu-kvm).
     */
    else
      single_element ("emulator", QEMU);
#endif

    /* Add a random number generator (backend for virtio-rng).  This
     * requires Cole Robinson's patch to permit /dev/urandom to be
     * used, which was added in libvirt 1.3.4.
     */
    if (guestfs_int_version_ge (&params->data->libvirt_version, 1, 3, 4)) {
      start_element ("rng") {
        attribute ("model", "virtio");
        start_element ("backend") {
          attribute ("model", "random");
          string ("/dev/urandom");
        } end_element ();
      } end_element ();
    }

    /* virtio-scsi controller. */
    start_element ("controller") {
      attribute ("type", "scsi");
      attribute ("index", "0");
      attribute ("model", "virtio-scsi");
    } end_element ();

    /* Disks. */
    ITER_DRIVES (g, i, drv) {
      if (construct_libvirt_xml_disk (g, params->data, xo, drv, i) == -1)
        return -1;
    }

    if (params->appliance_overlay) {
      /* Appliance disk. */
      if (construct_libvirt_xml_appliance (g, params, xo) == -1)
        return -1;
    }

#ifndef __s390x__
    /* Console. */
    start_element ("serial") {
      attribute ("type", "unix");
      start_element ("source") {
        attribute ("mode", "connect");
        attribute ("path", params->data->console_path);
      } end_element ();
      start_element ("target") {
        attribute ("port", "0");
      } end_element ();
    } end_element ();
#else
    /* https://bugzilla.redhat.com/show_bug.cgi?id=1376547#c14
     * and https://libvirt.org/formatdomain.html#elementCharConsole
     */
    start_element ("console") {
      attribute ("type", "unix");
      start_element ("source") {
        attribute ("mode", "connect");
        attribute ("path", params->data->console_path);
      } end_element ();
      start_element ("target") {
        attribute ("type", "sclp");
        attribute ("port", "0");
      } end_element ();
    } end_element ();
#endif

    /* Virtio-serial for guestfsd communication. */
    start_element ("channel") {
      attribute ("type", "unix");
      start_element ("source") {
        attribute ("mode", "connect");
        attribute ("path", params->data->guestfsd_path);
      } end_element ();
      start_element ("target") {
        attribute ("type", "virtio");
        attribute ("name", "org.libguestfs.channel.0");
      } end_element ();
    } end_element ();

    /* Virtio-net NIC with SLIRP (= userspace) back-end, if networking is
     * enabled. Starting with libvirt 3.8.0, we can specify the network address
     * and prefix for SLIRP in the domain XML. Therefore, we can add the NIC
     * via the standard <interface> element rather than <qemu:commandline>, and
     * so libvirt can manage the PCI address of the virtio-net NIC like the PCI
     * addresses of all other devices. Refer to RHBZ#2034160.
     */
    if (g->enable_network &&
        guestfs_int_version_ge (&params->data->libvirt_version, 3, 8, 0)) {
      start_element ("interface") {
        attribute ("type", "user");
        start_element ("model") {
          attribute ("type", "virtio");
        } end_element ();
        start_element ("ip") {
          attribute ("family", "ipv4");
          attribute ("address", NETWORK_ADDRESS);
          attribute ("prefix", NETWORK_PREFIX);
        } end_element ();
      } end_element ();
    }

    /* Libvirt adds some devices by default.  Indicate to libvirt
     * that we don't want them.
     */
    start_element ("controller") {
      attribute ("type", "usb");
      attribute ("model", "none");
    } end_element ();

    start_element ("memballoon") {
      attribute ("model", "none");
    } end_element ();

  } end_element (); /* </devices> */

  return 0;
}

static int
construct_libvirt_xml_disk (guestfs_h *g,
                            const struct backend_libvirt_data *data,
                            xmlTextWriterPtr xo,
                            struct drive *drv, size_t drv_index)
{
  const char *protocol_str;
  CLEANUP_FREE char *path = NULL;
  int is_host_device;
  CLEANUP_FREE char *format = NULL;
  const char *type, *uuid;
  int r;

  start_element ("disk") {
    attribute ("device", "disk");

    if (drv->overlay) {
      /* Overlay to protect read-only backing disk.  The format of the
       * overlay is always qcow2.
       */
      attribute ("type", "file");

      start_element ("source") {
        attribute ("file", drv->overlay);
        if (construct_libvirt_xml_disk_source_seclabel (g, data, xo) == -1)
          return -1;
      } end_element ();

      if (construct_libvirt_xml_disk_target (g, xo, drv_index) == -1)
        return -1;

      if (construct_libvirt_xml_disk_driver_qemu (g, data, drv,
                                                  xo, "qcow2", "unsafe",
                                                  discard_disable, false)
          == -1)
        return -1;
    }
    else {
      /* Not an overlay, a writable disk. */

      switch (drv->src.protocol) {
      case drive_protocol_file:
        /* Change the libvirt XML according to whether the host path is
         * a device or a file.  For devices, use:
         *   <disk type=block device=disk>
         *     <source dev=[path]>
         * For files, use:
         *   <disk type=file device=disk>
         *     <source file=[path]>
         */
        is_host_device = is_blk (drv->src.u.path);

        if (!is_host_device) {
          path = realpath (drv->src.u.path, NULL);
          if (path == NULL) {
            perrorf (g, _("realpath: could not convert ‘%s’ to absolute path"),
                     drv->src.u.path);
            return -1;
          }

          attribute ("type", "file");

          start_element ("source") {
            attribute ("file", path);
            if (construct_libvirt_xml_disk_source_seclabel (g, data, xo) == -1)
              return -1;
          } end_element ();
        }
        else {
          attribute ("type", "block");

          start_element ("source") {
            attribute ("dev", drv->src.u.path);
            if (construct_libvirt_xml_disk_source_seclabel (g, data, xo) == -1)
              return -1;
          } end_element ();
        }
        break;

        /* For network protocols:
         *   <disk type=network device=disk>
         *     <source protocol=[protocol] [name=exportname]>
         * and then zero or more of:
         *       <host name='example.com' port='10809'/>
         * or:
         *       <host transport='unix' socket='/path/to/socket'/>
         */
      case drive_protocol_gluster:
        protocol_str = "gluster"; goto network_protocols;
      case drive_protocol_iscsi:
        protocol_str = "iscsi"; goto network_protocols;
      case drive_protocol_nbd:
        protocol_str = "nbd"; goto network_protocols;
      case drive_protocol_rbd:
        protocol_str = "rbd"; goto network_protocols;
      case drive_protocol_sheepdog:
        protocol_str = "sheepdog"; goto network_protocols;
      case drive_protocol_ssh:
        protocol_str = "ssh";
        /*FALLTHROUGH*/
      network_protocols:
        attribute ("type", "network");

        start_element ("source") {
          attribute ("protocol", protocol_str);
          if (STRNEQ (drv->src.u.exportname, ""))
            attribute ("name", drv->src.u.exportname);
          if (construct_libvirt_xml_disk_source_hosts (g, xo,
                                                       &drv->src) == -1)
            return -1;
          if (construct_libvirt_xml_disk_source_seclabel (g, data, xo) == -1)
            return -1;
        } end_element ();

        if (drv->src.username != NULL) {
          start_element ("auth") {
            attribute ("username", drv->src.username);
            r = find_secret (g, data, drv, &type, &uuid);
            if (r == -1)
              return -1;
            if (r == 1) {
              start_element ("secret") {
                attribute ("type", type);
                attribute ("uuid", uuid);
              } end_element ();
            }
          } end_element ();
        }
        break;

        /* libvirt doesn't support the qemu curl driver yet.  Give a
         * reasonable error message instead of trying and failing.
         */
      case drive_protocol_ftp:
      case drive_protocol_ftps:
      case drive_protocol_http:
      case drive_protocol_https:
      case drive_protocol_tftp:
        error (g, _("libvirt does not support the qemu curl driver protocols (ftp, http, etc.); try setting LIBGUESTFS_BACKEND=direct"));
        return -1;
      }

      if (construct_libvirt_xml_disk_target (g, xo, drv_index) == -1)
        return -1;

      format = get_source_format_or_autodetect (g, drv);
      if (!format)
        return -1;

      if (construct_libvirt_xml_disk_driver_qemu (g, data, drv, xo, format,
                                                  drv->cachemode ? : "writeback",
                                                  drv->discard,
                                                  drv->copyonread)
          == -1)
        return -1;
    }

    if (drv->disk_label)
      single_element ("serial", drv->disk_label);

    if (construct_libvirt_xml_disk_address (g, xo, drv_index) == -1)
      return -1;

    if (construct_libvirt_xml_disk_blockio (g, xo, drv->blocksize) == -1)
      return -1;

  } end_element (); /* </disk> */

  return 0;
}

static int
construct_libvirt_xml_disk_target (guestfs_h *g, xmlTextWriterPtr xo,
                                   size_t drv_index)
{
  char drive_name[64] = "sd";

  guestfs_int_drive_name (drv_index, &drive_name[2]);

  start_element ("target") {
    attribute ("dev", drive_name);
    attribute ("bus", "scsi");
  } end_element ();

  return 0;
}

static int
construct_libvirt_xml_disk_driver_qemu (guestfs_h *g,
                                        const struct backend_libvirt_data *data,
                                        struct drive *drv,
                                        xmlTextWriterPtr xo,
                                        const char *format,
                                        const char *cachemode,
                                        enum discard discard,
                                        bool copyonread)
{
  bool discard_unmap = false;

  /* When adding the appliance disk, we don't have a 'drv' struct.
   * However the caller will use discard_disable, so we don't need it.
   */
  assert (discard == discard_disable || drv != NULL);

  switch (discard) {
  case discard_disable:
    /* Since the default is always discard=ignore, don't specify it
     * in the XML.
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
      discard_unmap = true;
    break;
  }

  start_element ("driver") {
    attribute ("name", "qemu");
    attribute ("type", format);
    attribute ("cache", cachemode);
    if (discard_unmap)
      attribute ("discard", "unmap");
    if (copyonread)
      attribute ("copy_on_read", "on");
  } end_element ();

  return 0;
}

static int
construct_libvirt_xml_disk_address (guestfs_h *g, xmlTextWriterPtr xo,
                                    size_t drv_index)
{
  start_element ("address") {
    attribute ("type", "drive");

    /* "controller" refers back to <controller type=scsi index=0
     * model=virtio-scsi/> which was added above.
     *
     * We could add more controllers, but it's a little inflexible
     * since each would require a PCI slot and we'd have to decide in
     * advance how many controllers to add, so best to leave this as 0.
     */
    attribute ("controller", "0");

    /* libvirt "bus" == qemu "channel".  virtio-scsi in qemu only uses
     * the channel for spapr_vscsi, and enforces channel=0 on all
     * other platforms.  You cannot change this.
     */
    attribute ("bus", "0");

    /* libvirt "target" == qemu "scsi-id" (internally in the qemu
     * virtio-scsi driver, this is the ".id" field).  This is a number
     * in the range 0-255.
     */
    attribute_format ("target", "%zu", drv_index);

    /* libvirt "unit" == qemu "lun".  This is the SCSI logical unit
     * number, which is a number in the range 0..16383.
     */
    attribute ("unit", "0");
  } end_element ();

  return 0;
}

static int
construct_libvirt_xml_disk_blockio (guestfs_h *g, xmlTextWriterPtr xo,
                                    int blocksize)
{
  if (blocksize) {
    start_element ("blockio") {
        attribute_format ("physical_block_size", "%d", blocksize);
        attribute_format ("logical_block_size", "%d", blocksize);
    } end_element ();
  }

  return 0;
}

static int
construct_libvirt_xml_disk_source_hosts (guestfs_h *g,
                                         xmlTextWriterPtr xo,
                                         const struct drive_source *src)
{
  size_t i;

  for (i = 0; i < src->nr_servers; ++i) {
    start_element ("host") {
      switch (src->servers[i].transport) {
      case drive_transport_none:
      case drive_transport_tcp: {
        attribute ("name", src->servers[i].u.hostname);
        if (src->servers[i].port > 0)
          attribute_format ("port", "%d", src->servers[i].port);
        break;
      }

      case drive_transport_unix: {
        /* libvirt requires sockets to be specified as an absolute path
         * (RHBZ#1588451).
         */
        const char *socket = src->servers[i].u.socket;
        CLEANUP_FREE char *abs_socket = realpath (socket, NULL);

        if (abs_socket == NULL) {
          perrorf (g, _("realpath: could not convert ‘%s’ to absolute path"),
                   socket);
          return -1;
        }

        attribute ("transport", "unix");
        attribute ("socket", abs_socket);
        break;
      }
      }

    } end_element ();
  }

  return 0;
}

static int
construct_libvirt_xml_disk_source_seclabel (guestfs_h *g,
                                            const struct backend_libvirt_data *data,
                                            xmlTextWriterPtr xo)
{
  if (data->selinux_norelabel_disks) {
    start_element ("seclabel") {
      attribute ("model", "selinux");
      attribute ("relabel", "no");
    } end_element ();
  }

  return 0;
}

static int
construct_libvirt_xml_appliance (guestfs_h *g,
                                 const struct libvirt_xml_params *params,
                                 xmlTextWriterPtr xo)
{
  start_element ("disk") {
    attribute ("type", "file");
    attribute ("device", "disk");

    start_element ("source") {
      attribute ("file", params->appliance_overlay);
    } end_element ();

    start_element ("target") {
      attribute ("dev", &params->appliance_dev[5]);
      attribute ("bus", "scsi");
    } end_element ();

    if (construct_libvirt_xml_disk_driver_qemu (g, params->data, NULL, xo,
                                                "qcow2", "unsafe",
                                                discard_disable, false) == -1)
      return -1;

    if (construct_libvirt_xml_disk_address (g, xo, params->appliance_index)
        == -1)
      return -1;

  } end_element ();

  return 0;
}

static int
construct_libvirt_xml_qemu_cmdline (guestfs_h *g,
                                    const struct libvirt_xml_params *params,
                                    xmlTextWriterPtr xo)
{
  struct hv_param *hp;
  CLEANUP_FREE char *tmpdir = NULL;

  start_element ("qemu:commandline") {

    /* We need to ensure the snapshots are created in the persistent
     * temporary directory (RHBZ#856619).  We must set one, because
     * otherwise libvirt will use a random TMPDIR (RHBZ#865464).
     */
    tmpdir = guestfs_get_cachedir (g);

    start_element ("qemu:env") {
      attribute ("name", "TMPDIR");
      attribute ("value", tmpdir);
    } end_element ();

    /* Workaround because libvirt user networking cannot specify "net="
     * parameter. Necessary only before libvirt 3.8.0; refer to RHBZ#2034160.
     */
    if (g->enable_network &&
        !guestfs_int_version_ge (&params->data->libvirt_version, 3, 8, 0)) {
      start_element ("qemu:arg") {
        attribute ("value", "-netdev");
      } end_element ();

      start_element ("qemu:arg") {
        attribute ("value",
                   "user,id=usernet,net=" NETWORK_ADDRESS "/" NETWORK_PREFIX);
      } end_element ();

      start_element ("qemu:arg") {
        attribute ("value", "-device");
      } end_element ();

      start_element ("qemu:arg") {
        attribute ("value", (VIRTIO_DEVICE_NAME ("virtio-net")
                             ",netdev=usernet"
                             VIRTIO_NET_PCI_ADDR));
      } end_element ();
    }

    /* The qemu command line arguments requested by the caller. */
    for (hp = g->hv_params; hp; hp = hp->next) {
      start_element ("qemu:arg") {
        attribute ("value", hp->hv_param);
      } end_element ();

      if (hp->hv_value) {
        start_element ("qemu:arg") {
          attribute ("value", hp->hv_value);
        } end_element ();
      }
    }
  } end_element (); /* </qemu:commandline> */

  return 0;
}

static int
construct_libvirt_xml_secret (guestfs_h *g,
                              const struct backend_libvirt_data *data,
                              const struct drive *drv,
                              xmlTextWriterPtr xo)
{
  start_element ("secret") {
    attribute ("ephemeral", "yes");
    attribute ("private", "yes");
    single_element_format ("description",
                           "guestfs secret associated with %s %s",
                           data->name, drv->src.u.path);
  } end_element ();

  return 0;
}

/* If drv->src.secret != NULL, store the secret in libvirt, and save
 * the UUID so we can retrieve it later.  Also there is some slight
 * variation depending on the protocol.  See
 * http://libvirt.org/formatsecret.html
 */
static int
add_secret (guestfs_h *g, virConnectPtr conn,
            struct backend_libvirt_data *data, const struct drive *drv)
{
  CLEANUP_XMLBUFFERFREE xmlBufferPtr xb = NULL;
  xmlOutputBufferPtr ob;
  CLEANUP_XMLFREETEXTWRITER xmlTextWriterPtr xo = NULL;
  CLEANUP_FREE xmlChar *xml = NULL;
  CLEANUP_VIRSECRETFREE virSecretPtr secret_obj = NULL;
  const char *secret = drv->src.secret;
  CLEANUP_FREE unsigned char *secret_raw = NULL;
  size_t secret_raw_len = 0;
  size_t i;

  if (secret == NULL)
    return 0;

  /* If it was already stored, don't create another secret. */
  if (have_secret (g, data, drv))
    return 0;

  /* Create the XML for the secret. */
  xb = xmlBufferCreate ();
  if (xb == NULL) {
    perrorf (g, "xmlBufferCreate");
    return -1;
  }
  ob = xmlOutputBufferCreateBuffer (xb, NULL);
  if (ob == NULL) {
    perrorf (g, "xmlOutputBufferCreateBuffer");
    return -1;
  }
  xo = xmlNewTextWriter (ob);
  if (xo == NULL) {
    perrorf (g, "xmlNewTextWriter");
    return -1;
  }

  if (xmlTextWriterSetIndent (xo, 1) == -1 ||
      xmlTextWriterSetIndentString (xo, BAD_CAST "  ") == -1) {
    perrorf (g, "could not set XML indent");
    return -1;
  }
  if (xmlTextWriterStartDocument (xo, NULL, NULL, NULL) == -1) {
    perrorf (g, "xmlTextWriterStartDocument");
    return -1;
  }

  if (construct_libvirt_xml_secret (g, data, drv, xo) == -1)
    return -1;

  if (xmlTextWriterEndDocument (xo) == -1) {
    perrorf (g, "xmlTextWriterEndDocument");
    return -1;
  }
  xml = xmlBufferDetach (xb);
  if (xml == NULL) {
    perrorf (g, "xmlBufferDetach");
    return -1;
  }

  debug (g, "libvirt secret XML:\n%s", xml);

  /* Pass the XML to libvirt. */
  secret_obj = virSecretDefineXML (conn, (const char *) xml, 0);
  if (secret_obj == NULL) {
    libvirt_error (g, _("could not define libvirt secret"));
    return -1;
  }

  /* For Ceph, we have to base64 decode the secret.  For others, we
   * currently just pass the secret straight through.
   */
  switch (drv->src.protocol) {
  case drive_protocol_rbd:
    if (!base64_decode_alloc (secret, strlen (secret),
                              (char **) &secret_raw, &secret_raw_len)) {
      error (g, _("rbd protocol secret must be base64 encoded"));
      return -1;
    }
    if (secret_raw == NULL) {
      error (g, _("base64_decode_alloc: %m"));
      return -1;
    }
    break;
  case drive_protocol_file:
  case drive_protocol_ftp:
  case drive_protocol_ftps:
  case drive_protocol_gluster:
  case drive_protocol_http:
  case drive_protocol_https:
  case drive_protocol_iscsi:
  case drive_protocol_nbd:
  case drive_protocol_sheepdog:
  case drive_protocol_ssh:
  case drive_protocol_tftp:
    secret_raw = (unsigned char *) safe_strdup (g, secret);
    secret_raw_len = strlen (secret);
  }

  /* Set the secret. */
  if (virSecretSetValue (secret_obj, secret_raw, secret_raw_len, 0) == -1) {
    libvirt_error (g, _("could not set libvirt secret value"));
    return -1;
  }

  /* Get back the UUID and save it in the private data. */
  i = data->nr_secrets;
  data->nr_secrets++;
  data->secrets =
    safe_realloc (g, data->secrets, sizeof (struct secret) * data->nr_secrets);

  data->secrets[i].secret = safe_strdup (g, secret);

  if (virSecretGetUUIDString (secret_obj, data->secrets[i].uuid) == -1) {
    libvirt_error (g, _("could not get UUID from libvirt secret"));
    return -1;
  }

  return 0;
}

static int
have_secret (guestfs_h *g,
             const struct backend_libvirt_data *data, const struct drive *drv)
{
  size_t i;

  if (drv->src.secret == NULL)
    return 0;

  for (i = 0; i < data->nr_secrets; ++i) {
    if (STREQ (data->secrets[i].secret, drv->src.secret))
      return 1;
  }

  return 0;
}

/* Find a secret previously stored in libvirt.  Returns the
 * <secret type=... uuid=...> attributes.  This function returns -1
 * if there was an error, 0 if there is no secret, and 1 if the
 * secret was found and returned.
 */
static int
find_secret (guestfs_h *g,
             const struct backend_libvirt_data *data, const struct drive *drv,
             const char **type, const char **uuid)
{
  size_t i;

  if (drv->src.secret == NULL)
    return 0;

  for (i = 0; i < data->nr_secrets; ++i) {
    if (STREQ (data->secrets[i].secret, drv->src.secret)) {
      *uuid = data->secrets[i].uuid;

      *type = "volume";

      switch (drv->src.protocol) {
      case drive_protocol_rbd:
        *type = "ceph";
        break;
      case drive_protocol_iscsi:
        *type = "iscsi";
        break;
      case drive_protocol_file:
      case drive_protocol_ftp:
      case drive_protocol_ftps:
      case drive_protocol_gluster:
      case drive_protocol_http:
      case drive_protocol_https:
      case drive_protocol_nbd:
      case drive_protocol_sheepdog:
      case drive_protocol_ssh:
      case drive_protocol_tftp:
        /* set to a default value above */ ;
      }

      return 1;
    }
  }

  return 0;
}

static int
is_blk (const char *path)
{
  struct stat statbuf;

  if (stat (path, &statbuf) == -1)
    return 0;
  return S_ISBLK (statbuf.st_mode);
}

static void
ignore_errors (void *ignore, virErrorPtr ignore2)
{
  /* empty */
}

static int destroy_domain (guestfs_h *g, virDomainPtr dom, int check_for_errors);

static int
shutdown_libvirt (guestfs_h *g, void *datav, int check_for_errors)
{
  struct backend_libvirt_data *data = datav;
  virConnectPtr conn = data->conn;
  virDomainPtr dom = data->dom;
  size_t i;
  int ret = 0;

  /* Note that we can be called back very early in launch (specifically
   * from launch_libvirt itself), when conn and dom might be NULL.
   */
  if (dom != NULL) {
    ret = destroy_domain (g, dom, check_for_errors);
    virDomainFree (dom);
  }
  if (conn != NULL)
    virConnectClose (conn);

  if (data->guestfsd_path[0] != '\0') {
    unlink (data->guestfsd_path);
    data->guestfsd_path[0] = '\0';
  }

  if (data->console_path[0] != '\0') {
    unlink (data->console_path);
    data->console_path[0] = '\0';
  }

  data->conn = NULL;
  data->dom = NULL;

  free (data->selinux_label);
  data->selinux_label = NULL;
  free (data->selinux_imagelabel);
  data->selinux_imagelabel = NULL;

  for (i = 0; i < data->nr_secrets; ++i)
    free (data->secrets[i].secret);
  free (data->secrets);
  data->secrets = NULL;
  data->nr_secrets = 0;

  free (data->uefi_code);
  data->uefi_code = NULL;
  free (data->uefi_vars);
  data->uefi_vars = NULL;

  free (data->default_qemu);
  data->default_qemu = NULL;

  guestfs_int_free_string_list (data->firmware_autoselect);
  data->firmware_autoselect = NULL;

  return ret;
}

/* Wrapper around virDomainDestroy which handles errors and retries.. */
static int
destroy_domain (guestfs_h *g, virDomainPtr dom, int check_for_errors)
{
  const int flags = check_for_errors ? VIR_DOMAIN_DESTROY_GRACEFUL : 0;
  virErrorPtr err;

 again:
  debug (g, "calling virDomainDestroy flags=%s",
         check_for_errors ? "VIR_DOMAIN_DESTROY_GRACEFUL" : "0");
  if (virDomainDestroyFlags (dom, flags) == 0)
    return 0;

  /* Error returned by virDomainDestroyFlags ... */
  err = virGetLastError ();

  /* Retry (indefinitely) if we're just waiting for qemu to shut down.  See:
   * https://www.redhat.com/archives/libvir-list/2016-January/msg00767.html
   */
  if (err && err->code == VIR_ERR_SYSTEM_ERROR && err->int1 == EBUSY)
    goto again;

  /* "Domain not found" is not treated as an error. */
  if (err && err->code == VIR_ERR_NO_DOMAIN)
    return 0;

  libvirt_error (g, _("could not destroy libvirt domain"));
  return -1;
}

/* Wrapper around error() which produces better errors for
 * libvirt functions.
 */
static void
libvirt_error (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;
  virErrorPtr err;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0)
    msg = safe_asprintf (g,
                         _("%s: internal error forming error message"),
                         __func__);

  /* In all recent libvirt, this retrieves the thread-local error. */
  err = virGetLastError ();
  if (err)
    error (g, "%s: %s [code=%d int1=%d]",
           msg, err->message, err->code, err->int1);
  else
    error (g, "%s", msg);

  /* NB. 'err' must not be freed! */
  free (msg);
}

/* Same as 'libvirt_error' but calls debug instead. */
static void
libvirt_debug (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;
  virErrorPtr err;

  if (!g->verbose)
    return;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0)
    msg = safe_asprintf (g,
                         _("%s: internal error forming error message"),
                         __func__);

  /* In all recent libvirt, this retrieves the thread-local error. */
  err = virGetLastError ();
  if (err)
    debug (g, "%s: %s [code=%d int1=%d]",
           msg, err->message, err->code, err->int1);
  else
    debug (g, "%s", msg);

  /* NB. 'err' must not be freed! */
  free (msg);
}

#if HAVE_LIBSELINUX
static void
selinux_warning (guestfs_h *g, const char *func,
                 const char *selinux_op, const char *data)
{
  debug (g, "%s: %s failed: %s: %m"
         " [you can ignore this message if you are not using SELinux + sVirt]",
         func, selinux_op, data ? data : "(none)");
}
#endif

/* This backend assumes virtio-scsi is available. */
static int
max_disks_libvirt (guestfs_h *g, void *datav)
{
  /* target is in the range 0-255, but one target is reserved for the
   * appliance.
   */
  return 255;
}

static struct backend_ops backend_libvirt_ops = {
  .data_size = sizeof (struct backend_libvirt_data),
  .create_cow_overlay = create_cow_overlay_libvirt,
  .launch = launch_libvirt,
  .shutdown = shutdown_libvirt,
  .max_disks = max_disks_libvirt,
};

void
guestfs_int_init_libvirt_backend (void)
{
  guestfs_int_register_backend ("libvirt", &backend_libvirt_ops);
}

#endif /* HAVE_LIBVIRT */
