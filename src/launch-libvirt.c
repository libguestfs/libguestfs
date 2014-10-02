/* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <fcntl.h>
#include <limits.h>
#include <grp.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <assert.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include <libxml/xmlIO.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>

#if HAVE_LIBSELINUX
#include <selinux/selinux.h>
#include <selinux/context.h>
#endif

#include "glthread/lock.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Check minimum required version of libvirt.  The libvirt backend
 * is new and not the default, so we can get away with forcing
 * people who want to try it to have a reasonably new version of
 * libvirt, so we don't have to work around any bugs in libvirt.
 *
 * This is also checked at runtime because you can dynamically link
 * with a different version from what you were compiled with.
 */
#define MIN_LIBVIRT_MAJOR 0
#define MIN_LIBVIRT_MINOR 10
#define MIN_LIBVIRT_MICRO 2 /* XXX patches in > 2 already */
#define MIN_LIBVIRT_VERSION (MIN_LIBVIRT_MAJOR * 1000000 + \
                             MIN_LIBVIRT_MINOR * 1000 + \
                             MIN_LIBVIRT_MICRO)

#if defined(HAVE_LIBVIRT) && \
  LIBVIR_VERSION_NUMBER >= MIN_LIBVIRT_VERSION

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
  unsigned long qemu_version;   /* qemu version (from libvirt) */
  char *uefi_code;		/* UEFI (firmware) code and variables. */
  char *uefi_vars;
};

/* Parameters passed to construct_libvirt_xml and subfunctions.  We
 * keep them all in a structure for convenience!
 */
struct libvirt_xml_params {
  struct backend_libvirt_data *data;
  char *kernel;                 /* paths to kernel, dtb and initrd */
  char *dtb;
  char *initrd;
  char *appliance_overlay;      /* path to qcow2 overlay backed by appliance */
  char appliance_dev[64];       /* appliance device name */
  size_t appliance_index;       /* index of appliance */
  char guestfsd_path[UNIX_PATH_MAX]; /* paths to sockets */
  char console_path[UNIX_PATH_MAX];
  bool enable_svirt;            /* false if we decided to disable sVirt */
  bool current_proc_is_root;    /* true = euid is root */
};

static int parse_capabilities (guestfs_h *g, const char *capabilities_xml, struct backend_libvirt_data *data);
static xmlChar *construct_libvirt_xml (guestfs_h *g, const struct libvirt_xml_params *params);
static void debug_appliance_permissions (guestfs_h *g);
static void debug_socket_permissions (guestfs_h *g);
static void libvirt_error (guestfs_h *g, const char *fs, ...) __attribute__((format (printf,2,3)));
static void libvirt_debug (guestfs_h *g, const char *fs, ...) __attribute__((format (printf,2,3)));
static int is_custom_hv (guestfs_h *g);
static int is_blk (const char *path);
static void ignore_errors (void *ignore, virErrorPtr ignore2);
static void set_socket_create_context (guestfs_h *g);
static void clear_socket_create_context (guestfs_h *g);

#if HAVE_LIBSELINUX
static void selinux_warning (guestfs_h *g, const char *func, const char *selinux_op, const char *data);
#endif

static char *
make_qcow2_overlay (guestfs_h *g, const char *backing_drive,
                    const char *format)
{
  char *overlay;
  struct guestfs_disk_create_argv optargs;

  if (guestfs___lazy_make_tmpdir (g) == -1)
    return NULL;

  overlay = safe_asprintf (g, "%s/overlay%d", g->tmpdir, ++g->unique);

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
  char *overlay;

  backing_drive = guestfs___drive_source_qemu_param (g, &drv->src);
  if (!backing_drive)
    return NULL;

  overlay = make_qcow2_overlay (g, backing_drive, drv->src.format);
  if (!overlay)
    return NULL;

#if HAVE_LIBSELINUX
  if (data->selinux_imagelabel) {
    debug (g, "setting SELinux label on %s to %s",
           overlay, data->selinux_imagelabel);
    if (setfilecon (overlay,
                    (security_context_t) data->selinux_imagelabel) == -1)
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
  unsigned long version;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  CLEANUP_FREE char *capabilities_xml = NULL;
  struct libvirt_xml_params params = {
    .data = data,
    .kernel = NULL,
    .dtb = NULL,
    .initrd = NULL,
    .appliance_overlay = NULL,
  };
  CLEANUP_FREE xmlChar *xml = NULL;
  CLEANUP_FREE char *appliance = NULL;
  struct sockaddr_un addr;
  int r;
  uint32_t size;
  CLEANUP_FREE void *buf = NULL;

  params.current_proc_is_root = geteuid () == 0;

  /* XXX: It should be possible to make this work. */
  if (g->direct_mode) {
    error (g, _("direct mode flag is not supported yet for libvirt backend"));
    return -1;
  }

  virGetVersion (&version, NULL, NULL);
  debug (g, "libvirt version = %lu (%lu.%lu.%lu)",
         version,
         version / 1000000UL, version / 1000UL % 1000UL, version % 1000UL);
  if (version < MIN_LIBVIRT_VERSION) {
    error (g, _("you must have libvirt >= %d.%d.%d "
                "to use the 'libvirt' backend"),
           MIN_LIBVIRT_MAJOR, MIN_LIBVIRT_MINOR, MIN_LIBVIRT_MICRO);
    return -1;
  }

  guestfs___launch_send_progress (g, 0);
  TRACE0 (launch_libvirt_start);

  /* Create a random name for the guest. */
  memcpy (data->name, "guestfs-", 8);
  const size_t random_name_len =
    DOMAIN_NAME_LEN - 8 /* "guestfs-" */ - 1 /* \0 */;
  if (guestfs___random_string (&data->name[8], random_name_len) == -1) {
    perrorf (g, "guestfs___random_string");
    return -1;
  }
  debug (g, "guest random name = %s", data->name);

  if (g->verbose)
    guestfs___print_timestamped_message (g, "connect to libvirt");

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
  conn = guestfs___open_libvirt_connection (g, libvirt_uri, 0);
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
  if (virConnectGetVersion (conn, &data->qemu_version) == 0) {
    debug (g, "qemu version (reported by libvirt) = %lu (%lu.%lu.%lu)",
           data->qemu_version,
           data->qemu_version / 1000000UL,
           data->qemu_version / 1000UL % 1000UL,
           data->qemu_version % 1000UL);
  }
  else {
    libvirt_debug (g, "unable to read qemu version from libvirt");
    data->qemu_version = 0;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "get libvirt capabilities");

  capabilities_xml = virConnectGetCapabilities (conn);
  if (!capabilities_xml) {
    libvirt_error (g, _("could not get libvirt capabilities"));
    goto cleanup;
  }

  /* Parse capabilities XML.  This fills in various fields in 'params'
   * struct, and can also fail if we detect that the hypervisor cannot
   * run qemu guests (RHBZ#886915).
   */
  if (g->verbose)
    guestfs___print_timestamped_message (g, "parsing capabilities XML");

  if (parse_capabilities (g, capabilities_xml, data) == -1)
    goto cleanup;

  /* UEFI code and variables, on architectures where that is required. */
  if (guestfs___get_uefi (g, &data->uefi_code, &data->uefi_vars) == -1)
    goto cleanup;

  /* Misc backend settings. */
  guestfs_push_error_handler (g, NULL, NULL);
  data->selinux_label =
    guestfs_get_backend_setting (g, "internal_libvirt_label");
  data->selinux_imagelabel =
    guestfs_get_backend_setting (g, "internal_libvirt_imagelabel");
  data->selinux_norelabel_disks =
    guestfs___get_backend_setting_bool (g, "internal_libvirt_norelabel_disks");
  guestfs_pop_error_handler (g);

  /* Locate and/or build the appliance. */
  TRACE0 (launch_build_libvirt_appliance_start);

  if (g->verbose)
    guestfs___print_timestamped_message (g, "build appliance");

  if (guestfs___build_appliance (g, &params.kernel, &params.dtb,
				 &params.initrd, &appliance) == -1)
    goto cleanup;

  guestfs___launch_send_progress (g, 3);
  TRACE0 (launch_build_libvirt_appliance_end);

  /* Note that appliance can be NULL if using the old-style appliance. */
  if (appliance) {
    params.appliance_overlay = make_qcow2_overlay (g, appliance, "raw");
    if (!params.appliance_overlay)
      goto cleanup;
  }

  TRACE0 (launch_build_libvirt_qcow2_overlay_end);

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  snprintf (params.guestfsd_path, sizeof params.guestfsd_path,
            "%s/guestfsd.sock", g->tmpdir);
  unlink (params.guestfsd_path);

  set_socket_create_context (g);

  daemon_accept_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (daemon_accept_sock == -1) {
    perrorf (g, "socket");
    goto cleanup;
  }

  addr.sun_family = AF_UNIX;
  memcpy (addr.sun_path, params.guestfsd_path, UNIX_PATH_MAX);

  if (bind (daemon_accept_sock, &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (listen (daemon_accept_sock, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup;
  }

  /* For the serial console. */
  snprintf (params.console_path, sizeof params.console_path,
            "%s/console.sock", g->tmpdir);
  unlink (params.console_path);

  console_sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (console_sock == -1) {
    perrorf (g, "socket");
    goto cleanup;
  }

  addr.sun_family = AF_UNIX;
  memcpy (addr.sun_path, params.console_path, UNIX_PATH_MAX);

  if (bind (console_sock, &addr, sizeof addr) == -1) {
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

    if (chmod (params.guestfsd_path, 0660) == -1) {
      perrorf (g, "chmod: %s", params.guestfsd_path);
      goto cleanup;
    }

    if (chmod (params.console_path, 0660) == -1) {
      perrorf (g, "chmod: %s", params.console_path);
      goto cleanup;
    }

    grp = getgrnam ("qemu");
    if (grp != NULL) {
      if (chown (params.guestfsd_path, 0, grp->gr_gid) == -1) {
        perrorf (g, "chown: %s", params.guestfsd_path);
        goto cleanup;
      }
      if (chown (params.console_path, 0, grp->gr_gid) == -1) {
        perrorf (g, "chown: %s", params.console_path);
        goto cleanup;
      }
    } else
      debug (g, "cannot find group 'qemu'");
  }

  /* Construct the libvirt XML. */
  if (g->verbose)
    guestfs___print_timestamped_message (g, "create libvirt XML");

  params.appliance_index = g->nr_drives;
  strcpy (params.appliance_dev, "/dev/sd");
  guestfs___drive_name (params.appliance_index, &params.appliance_dev[7]);
  params.enable_svirt = ! is_custom_hv (g);

  xml = construct_libvirt_xml (g, &params);
  if (!xml)
    goto cleanup;

  /* Debug permissions and SELinux contexts on appliance and sockets. */
  if (g->verbose) {
    debug_appliance_permissions (g);
    debug_socket_permissions (g);
  }

  /* Launch the libvirt guest. */
  if (g->verbose)
    guestfs___print_timestamped_message (g, "launch libvirt guest");

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
    guestfs___new_conn_socket_listening (g, daemon_accept_sock, console_sock);
  if (!g->conn)
    goto cleanup;

  /* g->conn now owns these sockets. */
  daemon_accept_sock = console_sock = -1;

  r = g->conn->ops->accept_connection (g, g->conn);
  if (r == -1)
    goto cleanup;
  if (r == 0) {
    guestfs___launch_failed_error (g);
    goto cleanup;
  }

  /* NB: We reach here just because qemu has opened the socket.  It
   * does not mean the daemon is up until we read the
   * GUESTFS_LAUNCH_FLAG below.  Failures in qemu startup can still
   * happen even if we reach here, even early failures like not being
   * able to open a drive.
   */

  r = guestfs___recv_from_daemon (g, &size, &buf);

  if (r == -1) {
    guestfs___launch_failed_error (g);
    goto cleanup;
  }

  if (size != GUESTFS_LAUNCH_FLAG) {
    guestfs___launch_failed_error (g);
    goto cleanup;
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
    goto cleanup;
  }

  if (appliance)
    guestfs___add_dummy_appliance_drive (g);

  TRACE0 (launch_libvirt_end);

  guestfs___launch_send_progress (g, 12);

  data->conn = conn;
  data->dom = dom;

  free (params.kernel);
  free (params.dtb);
  free (params.initrd);
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
  free (params.dtb);
  free (params.initrd);
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

  /* This was RHBZ#886915: in that case the default libvirt URI
   * pointed to a Xen hypervisor, and so could not create the
   * appliance VM.
   */
  if (!seen_qemu && !seen_kvm) {
    error (g,
           _("libvirt hypervisor doesn't support qemu or KVM,\n"
             "so we cannot create the libguestfs appliance.\n"
             "The current backend is '%s'.\n"
             "Check that the PATH environment variable is set and contains\n"
             "the path to the qemu ('qemu-system-*') or KVM ('qemu-kvm', 'kvm' etc).\n"
             "Or: try setting:\n"
             "  export LIBGUESTFS_BACKEND=libvirt:qemu:///session\n"
             "Or: if you want to have libguestfs run qemu directly, try:\n"
             "  export LIBGUESTFS_BACKEND=direct\n"
             "For further help, read the guestfs(3) man page and libguestfs FAQ."),
           guestfs_get_backend (g));
    return -1;
  }

  force_tcg = guestfs___get_backend_setting_bool (g, "force_tcg");
  if (force_tcg == -1)
    return -1;

  if (!force_tcg)
    data->is_kvm = seen_kvm;
  else
    data->is_kvm = 0;

  return 0;
}

static int
is_custom_hv (guestfs_h *g)
{
#ifdef QEMU
  return g->hv && STRNEQ (g->hv, QEMU);
#else
  return 1;
#endif
}

#if HAVE_LIBSELINUX

/* Set sVirt (SELinux) socket create context.  For details see:
 * https://bugzilla.redhat.com/show_bug.cgi?id=853393#c14
 */

#define SOCKET_CONTEXT "svirt_socket_t"

static void
set_socket_create_context (guestfs_h *g)
{
  security_context_t scon; /* this is actually a 'char *' */
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
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs___new_command (g);
  CLEANUP_FREE char *cachedir = guestfs_get_cachedir (g);
  CLEANUP_FREE char *appliance = NULL;

  appliance = safe_asprintf (g, "%s/.guestfs-%d", cachedir, geteuid ());

  guestfs___cmd_add_arg (cmd, "ls");
  guestfs___cmd_add_arg (cmd, "-a");
  guestfs___cmd_add_arg (cmd, "-l");
  guestfs___cmd_add_arg (cmd, "-Z");
  guestfs___cmd_add_arg (cmd, appliance);
  guestfs___cmd_set_stdout_callback (cmd, debug_permissions_cb, NULL, 0);
  guestfs___cmd_run (cmd);
}

static void
debug_socket_permissions (guestfs_h *g)
{
  if (g->tmpdir) {
    CLEANUP_CMD_CLOSE struct command *cmd = guestfs___new_command (g);

    guestfs___cmd_add_arg (cmd, "ls");
    guestfs___cmd_add_arg (cmd, "-a");
    guestfs___cmd_add_arg (cmd, "-l");
    guestfs___cmd_add_arg (cmd, "-Z");
    guestfs___cmd_add_arg (cmd, g->tmpdir);
    guestfs___cmd_set_stdout_callback (cmd, debug_permissions_cb, NULL, 0);
    guestfs___cmd_run (cmd);
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
static int construct_libvirt_xml_disk_source_hosts (guestfs_h *g, xmlTextWriterPtr xo, const struct drive_source *src);
static int construct_libvirt_xml_disk_source_seclabel (guestfs_h *g, const struct backend_libvirt_data *data, xmlTextWriterPtr xo);
static int construct_libvirt_xml_appliance (guestfs_h *g, const struct libvirt_xml_params *params, xmlTextWriterPtr xo);

/* These macros make it easier to write XML, but they also make a lot
 * of assumptions:
 *
 * - The xmlTextWriterPtr is called 'xo'.  It is used implicitly.
 *
 * - The guestfs handle is called 'g'.  It is used implicitly for errors.
 *
 * - It is safe to 'return -1' on failure.  This is OK provided you
 *   always use CLEANUP_* macros.
 *
 * - All the "bad" casting is hidden inside the macros.
 */

/* <element */
#define start_element(element)                                        \
  if (xmlTextWriterStartElement (xo, BAD_CAST (element)) == -1) {     \
    xml_error ("xmlTextWriterStartElement");                          \
    return -1;                                                        \
  }                                                                   \
  do

/* finish current </element> */
#define end_element()                                                   \
  while (0);                                                            \
  do {                                                                  \
    if (xmlTextWriterEndElement (xo) == -1) {                           \
      xml_error ("xmlTextWriterEndElement");                            \
      return -1;                                                        \
    }                                                                   \
  } while (0)

/* <element/> */
#define empty_element(element) \
  do { start_element(element) {} end_element (); } while (0)

/* key=value attribute of the current element. */
#define attribute(key,value)                                            \
  if (xmlTextWriterWriteAttribute (xo, BAD_CAST (key), BAD_CAST (value)) == -1){\
    xml_error ("xmlTextWriterWriteAttribute");                          \
    return -1;                                                          \
  }

/* key=value, but value is a printf-style format string. */
#define attribute_format(key,fs,...)                                    \
  if (xmlTextWriterWriteFormatAttribute (xo, BAD_CAST (key),            \
                                         fs, ##__VA_ARGS__) == -1) {    \
    xml_error ("xmlTextWriterWriteFormatAttribute");                    \
    return -1;                                                          \
  }

/* attribute with namespace. */
#define attribute_ns(prefix,key,namespace_uri,value)                    \
  if (xmlTextWriterWriteAttributeNS (xo, BAD_CAST (prefix),             \
                                     BAD_CAST (key), BAD_CAST (namespace_uri), \
                                     BAD_CAST (value)) == -1) {         \
    xml_error ("xmlTextWriterWriteAttribute");                          \
    return -1;                                                          \
  }

/* A string, eg. within an element. */
#define string(str)                                                     \
  if (xmlTextWriterWriteString (xo, BAD_CAST (str)) == -1) {            \
    xml_error ("xmlTextWriterWriteString");                             \
    return -1;                                                          \
  }

/* A string, using printf-style formatting. */
#define string_format(fs,...)                                           \
  if (xmlTextWriterWriteFormatString (xo, fs, ##__VA_ARGS__) == -1) {   \
    xml_error ("xmlTextWriterWriteFormatString");                       \
    return -1;                                                          \
  }

#define xml_error(fn)                                                   \
    perrorf (g, _("%s:%d: error constructing libvirt XML near call to \"%s\""), \
             __FILE__, __LINE__, (fn));

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
  start_element ("name") {
    string (params->data->name);
  } end_element ();

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

  cpu_model = guestfs___get_cpu_model (params->data->is_kvm);
  if (cpu_model) {
    start_element ("cpu") {
      if (STREQ (cpu_model, "host")) {
        attribute ("mode", "host-passthrough");
        start_element ("model") {
          attribute ("fallback", "allow");
        } end_element ();
      }
      else {
        /* XXX This does not work on aarch64, see:
         * https://www.redhat.com/archives/libvirt-users/2014-August/msg00043.html
	 * https://bugzilla.redhat.com/show_bug.cgi?id=1184411
	 * Instead we hack around it using <qemu:commandline> below.
         */
#ifndef __aarch64__
        start_element ("model") {
          string (cpu_model);
        } end_element ();
#endif
      }
    } end_element ();
  }

  start_element ("vcpu") {
    string_format ("%d", g->smp);
  } end_element ();

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
  cmdline = guestfs___appliance_command_line (g, params->appliance_dev, flags);

  start_element ("os") {
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

      if (params->data->uefi_vars) {
	start_element ("nvram") {
	  string (params->data->uefi_vars);
	} end_element ();
      }
    }

    start_element ("kernel") {
      string (params->kernel);
    } end_element ();

    if (params->dtb) {
      start_element ("dtb") {
        string (params->dtb);
      } end_element ();
    }

    start_element ("initrd") {
      string (params->initrd);
    } end_element ();

    start_element ("cmdline") {
      string (cmdline);
    } end_element ();

#if defined(__i386__) || defined(__x86_64__)
    start_element ("bios") {
      attribute ("useserial", "yes");
    } end_element ();
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
      start_element ("label") {
        string (params->data->selinux_label);
      } end_element ();
      start_element ("imagelabel") {
        string (params->data->selinux_imagelabel);
      } end_element ();
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
  start_element ("on_reboot") {
    string ("destroy");
  } end_element ();

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
    if (is_custom_hv (g)) {
      start_element ("emulator") {
        string (g->hv);
      } end_element ();
    }
#if defined(__arm__)
    /* Hopefully temporary hack to make ARM work (otherwise libvirt
     * chooses to run /usr/bin/qemu-kvm).
     */
    else {
      start_element ("emulator") {
        string (QEMU);
      } end_element ();
    }
#endif

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

    /* Console. */
    start_element ("serial") {
      attribute ("type", "unix");
      start_element ("source") {
        attribute ("mode", "connect");
        attribute ("path", params->console_path);
      } end_element ();
      start_element ("target") {
        attribute ("port", "0");
      } end_element ();
    } end_element ();

    /* Virtio-serial for guestfsd communication. */
    start_element ("channel") {
      attribute ("type", "unix");
      start_element ("source") {
        attribute ("mode", "connect");
        attribute ("path", params->guestfsd_path);
      } end_element ();
      start_element ("target") {
        attribute ("type", "virtio");
        attribute ("name", "org.libguestfs.channel.0");
      } end_element ();
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

  /* XXX We probably could support this if we thought about it some more. */
  if (drv->iface) {
    error (g, _("'iface' parameter is not supported by the libvirt backend"));
    return -1;
  }

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
            perrorf (g, _("realpath: could not convert '%s' to absolute path"),
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
            /* TODO: write the drive secret, after first storing it separately
             * in libvirt
             */
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

      if (drv->src.format)
        format = safe_strdup (g, drv->src.format);
      else if (drv->src.protocol == drive_protocol_file) {
        /* libvirt has disabled the feature of detecting the disk format,
         * unless the administrator sets allow_disk_format_probing=1 in
         * qemu.conf.  There is no way to detect if this option is set, so we
         * have to do format detection here using qemu-img and pass that to
         * libvirt.
         *
         * This is still a security issue, so in most cases it is recommended
         * the users pass the format to libguestfs which will faithfully pass
         * that to libvirt and this function won't be used.
         */
        format = guestfs_disk_format (g, drv->src.u.path);
        if (!format)
          return -1;

        if (STREQ (format, "unknown")) {
          error (g, _("could not auto-detect the format.\n"
                      "If the format is known, pass the format to libguestfs, eg. using the\n"
                      "'--format' option, or via the optional 'format' argument to 'add-drive'."));
          return -1;
        }
      }
      else {
        error (g, _("could not auto-detect the format when using a non-file protocol.\n"
                    "If the format is known, pass the format to libguestfs, eg. using the\n"
                    "'--format' option, or via the optional 'format' argument to 'add-drive'."));
        return -1;
      }

      if (construct_libvirt_xml_disk_driver_qemu (g, data, drv, xo, format,
                                                  drv->cachemode ? : "writeback",
                                                  drv->discard, false)
          == -1)
        return -1;
    }

    if (drv->disk_label) {
      start_element ("serial") {
        string (drv->disk_label);
      } end_element ();
    }

    if (construct_libvirt_xml_disk_address (g, xo, drv_index) == -1)
      return -1;

  } end_element (); /* </disk> */

  return 0;
}

static int
construct_libvirt_xml_disk_target (guestfs_h *g, xmlTextWriterPtr xo,
                                   size_t drv_index)
{
  char drive_name[64] = "sd";

  guestfs___drive_name (drv_index, &drive_name[2]);

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
    if (!guestfs___discard_possible (g, drv, data->qemu_version))
      return -1;
    /*FALLTHROUGH*/
  case discard_besteffort:
    /* I believe from reading the code that this is always safe as
     * long as qemu >= 1.5.
     */
    if (data->qemu_version >= 1005000)
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
    attribute ("controller", "0");
    attribute ("bus", "0");
    attribute_format ("target", "%zu", drv_index);
    attribute ("unit", "0");
  } end_element ();

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
        attribute ("transport", "unix");
        attribute ("socket", src->servers[i].u.socket);
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

    empty_element ("shareable");

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
     * parameter.
     */
    if (g->enable_network) {
      start_element ("qemu:arg") {
        attribute ("value", "-netdev");
      } end_element ();

      start_element ("qemu:arg") {
        attribute ("value", "user,id=usernet,net=169.254.0.0/16");
      } end_element ();

      start_element ("qemu:arg") {
        attribute ("value", "-device");
      } end_element ();

      start_element ("qemu:arg") {
        attribute ("value", VIRTIO_NET ",netdev=usernet");
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

#ifdef __aarch64__
    /* This is a temporary hack until RHBZ#1184411 is resolved.
     * See comments above about cpu model and aarch64.
     */
    const char *cpu_model = guestfs___get_cpu_model (params->data->is_kvm);
    if (STRNEQ (cpu_model, "host")) {
      start_element ("qemu:arg") {
        attribute ("value", "-cpu");
      } end_element ();
      start_element ("qemu:arg") {
        attribute ("value", cpu_model);
      } end_element ();
    }
#endif

  } end_element (); /* </qemu:commandline> */

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

static int
shutdown_libvirt (guestfs_h *g, void *datav, int check_for_errors)
{
  struct backend_libvirt_data *data = datav;
  virConnectPtr conn = data->conn;
  virDomainPtr dom = data->dom;
  int ret = 0;
  int flags;

  /* Note that we can be called back very early in launch (specifically
   * from launch_libvirt itself), when conn and dom might be NULL.
   */

  if (dom != NULL) {
    flags = check_for_errors ? VIR_DOMAIN_DESTROY_GRACEFUL : 0;
    debug (g, "calling virDomainDestroy \"%s\" flags=%s",
           data->name, check_for_errors ? "VIR_DOMAIN_DESTROY_GRACEFUL" : "0");
    if (virDomainDestroyFlags (dom, flags) == -1) {
      libvirt_error (g, _("could not destroy libvirt domain"));
      ret = -1;
    }
    virDomainFree (dom);
  }

  if (conn != NULL)
    virConnectClose (conn);

  data->conn = NULL;
  data->dom = NULL;

  free (data->selinux_label);
  data->selinux_label = NULL;
  free (data->selinux_imagelabel);
  data->selinux_imagelabel = NULL;

  free (data->uefi_code);
  data->uefi_code = NULL;
  free (data->uefi_vars);
  data->uefi_vars = NULL;

  return ret;
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
    error (g, "%s: %s [code=%d domain=%d]",
           msg, err->message, err->code, err->domain);
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
    debug (g, "%s: %s [code=%d domain=%d]",
           msg, err->message, err->code, err->domain);
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
         " [you can ignore this UNLESS using SELinux + sVirt]",
         func, selinux_op, data ? data : "(none)");
}
#endif

/* This backend assumes virtio-scsi is available. */
static int
max_disks_libvirt (guestfs_h *g, void *datav)
{
  return 255;
}

static xmlChar *construct_libvirt_xml_hot_add_disk (guestfs_h *g, const struct backend_libvirt_data *data, struct drive *drv, size_t drv_index);

/* Hot-add a drive.  Note the appliance is up when this is called. */
static int
hot_add_drive_libvirt (guestfs_h *g, void *datav,
                       struct drive *drv, size_t drv_index)
{
  struct backend_libvirt_data *data = datav;
  virConnectPtr conn = data->conn;
  virDomainPtr dom = data->dom;
  CLEANUP_FREE xmlChar *xml = NULL;

  if (!conn || !dom) {
    /* This is essentially an internal error if it happens. */
    error (g, "%s: conn == NULL or dom == NULL", __func__);
    return -1;
  }

  /* Create the XML for the new disk. */
  xml = construct_libvirt_xml_hot_add_disk (g, data, drv, drv_index);
  if (xml == NULL)
    return -1;

  /* Attach it. */
  if (virDomainAttachDeviceFlags (dom, (char *) xml,
                                  VIR_DOMAIN_DEVICE_MODIFY_LIVE) == -1) {
    libvirt_error (g, _("could not attach disk to libvirt domain"));
    return -1;
  }

  return 0;
}

/* Hot-remove a drive.  Note the appliance is up when this is called. */
static int
hot_remove_drive_libvirt (guestfs_h *g, void *datav,
                          struct drive *drv, size_t drv_index)
{
  struct backend_libvirt_data *data = datav;
  virConnectPtr conn = data->conn;
  virDomainPtr dom = data->dom;
  CLEANUP_FREE xmlChar *xml = NULL;

  if (!conn || !dom) {
    /* This is essentially an internal error if it happens. */
    error (g, "%s: conn == NULL or dom == NULL", __func__);
    return -1;
  }

  /* Re-create the XML for the disk. */
  xml = construct_libvirt_xml_hot_add_disk (g, data, drv, drv_index);
  if (xml == NULL)
    return -1;

  /* Detach it. */
  if (virDomainDetachDeviceFlags (dom, (char *) xml,
                                  VIR_DOMAIN_DEVICE_MODIFY_LIVE) == -1) {
    libvirt_error (g, _("could not detach disk from libvirt domain"));
    return -1;
  }

  return 0;
}

static xmlChar *
construct_libvirt_xml_hot_add_disk (guestfs_h *g,
                                    const struct backend_libvirt_data *data,
                                    struct drive *drv,
                                    size_t drv_index)
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

  if (construct_libvirt_xml_disk (g, data, xo, drv, drv_index) == -1)
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

  debug (g, "hot-add disk XML:\n%s", ret);

  return ret;
}

static struct backend_ops backend_libvirt_ops = {
  .data_size = sizeof (struct backend_libvirt_data),
  .create_cow_overlay = create_cow_overlay_libvirt,
  .launch = launch_libvirt,
  .shutdown = shutdown_libvirt,
  .max_disks = max_disks_libvirt,
  .hot_add_drive = hot_add_drive_libvirt,
  .hot_remove_drive = hot_remove_drive_libvirt,
};

static void init_backend (void) __attribute__((constructor));
static void
init_backend (void)
{
  guestfs___register_backend ("libvirt", &backend_libvirt_ops);
}

#endif
