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
#include <stdarg.h>
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

#ifdef HAVE_LIBXML2
#include <libxml/xmlIO.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>
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
  LIBVIR_VERSION_NUMBER >= MIN_LIBVIRT_VERSION && \
  defined(HAVE_LIBXML2)

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

/* Pointed to by 'struct drive *' -> priv field. */
struct drive_libvirt {
  /* This is either the original path, made absolute.  Or for readonly
   * drives, it is an (absolute path to) the overlay file that we
   * create.  This is always non-NULL.
   */
  char *path;
  /* The format of priv->path. */
  char *format;
};

static xmlChar *construct_libvirt_xml (guestfs_h *g, const char *capabilities_xml, const char *kernel, const char *initrd, const char *appliance_overlay, const char *guestfsd_sock, const char *console_sock, int disable_svirt);
static void libvirt_error (guestfs_h *g, const char *fs, ...);
static int is_custom_qemu (guestfs_h *g);
static int is_blk (const char *path);
static int random_chars (char *ret, size_t len);
static void ignore_errors (void *ignore, virErrorPtr ignore2);
static char *make_qcow2_overlay (guestfs_h *g, const char *path, const char *format);
static int make_qcow2_overlay_for_drive (guestfs_h *g, struct drive *drv);
static void drive_free_priv (void *);

static int
launch_libvirt (guestfs_h *g, const char *libvirt_uri)
{
  unsigned long version;
  int is_root = geteuid () == 0;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  char *capabilities = NULL;
  xmlChar *xml = NULL;
  char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  char *appliance_overlay = NULL;
  char guestfsd_sock[256];
  char console_sock[256];
  struct sockaddr_un addr;
  int console = -1, r;
  uint32_t size;
  void *buf = NULL;
  int disable_svirt = is_custom_qemu (g);
  struct drive *drv;
  size_t i;

  /* At present you must add drives before starting the appliance.  In
   * future when we enable hotplugging you won't need to do this.
   */
  if (!g->nr_drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  /* XXX: It should be possible to make this work. */
  if (g->direct) {
    error (g, _("direct mode flag is not supported yet for libvirt attach method"));
    return -1;
  }

  virGetVersion (&version, NULL, NULL);
  debug (g, "libvirt version = %lu", version);
  if (version < MIN_LIBVIRT_VERSION) {
    error (g, _("you must have libvirt >= %d.%d.%d "
                "to use the 'libvirt' attach-method"),
           MIN_LIBVIRT_MAJOR, MIN_LIBVIRT_MINOR, MIN_LIBVIRT_MICRO);
    return -1;
  }

  guestfs___launch_send_progress (g, 0);
  TRACE0 (launch_libvirt_start);

  if (g->verbose)
    guestfs___print_timestamped_message (g, "connect to libvirt");

  /* Connect to libvirt, get capabilities. */
  /* XXX Support libvirt authentication in the future. */
  conn = virConnectOpen (libvirt_uri);
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

  if (g->verbose)
    guestfs___print_timestamped_message (g, "get libvirt capabilities");

  capabilities = virConnectGetCapabilities (conn);
  if (!capabilities) {
    libvirt_error (g, _("could not get libvirt capabilities"));
    goto cleanup;
  }

  /* Locate and/or build the appliance. */
  TRACE0 (launch_build_libvirt_appliance_start);

  if (g->verbose)
    guestfs___print_timestamped_message (g, "build appliance");

  if (guestfs___build_appliance (g, &kernel, &initrd, &appliance) == -1)
    goto cleanup;

  guestfs___launch_send_progress (g, 3);
  TRACE0 (launch_build_libvirt_appliance_end);

  /* Create overlays for read-only drives and the appliance.  This
   * works around lack of support for <transient/> disks in libvirt.
   */
  appliance_overlay = make_qcow2_overlay (g, appliance, "raw");
  if (!appliance_overlay)
    goto cleanup;

  ITER_DRIVES (g, i, drv) {
    if (make_qcow2_overlay_for_drive (g, drv) == -1)
      goto cleanup;
  }

  TRACE0 (launch_build_libvirt_qcow2_overlay_end);

  /* Using virtio-serial, we need to create a local Unix domain socket
   * for qemu to connect to.
   */
  snprintf (guestfsd_sock, sizeof guestfsd_sock, "%s/guestfsd.sock", g->tmpdir);
  unlink (guestfsd_sock);

  g->sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (g->sock == -1) {
    perrorf (g, "socket");
    goto cleanup;
  }

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, guestfsd_sock, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  if (bind (g->sock, &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (listen (g->sock, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup;
  }

  /* For the serial console. */
  snprintf (console_sock, sizeof console_sock, "%s/console.sock", g->tmpdir);
  unlink (console_sock);

  console = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (console == -1) {
    perrorf (g, "socket");
    goto cleanup;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, console_sock, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  if (bind (console, &addr, sizeof addr) == -1) {
    perrorf (g, "bind");
    goto cleanup;
  }

  if (listen (console, 1) == -1) {
    perrorf (g, "listen");
    goto cleanup;
  }

  /* libvirt, if running as root, will run the qemu process as
   * qemu.qemu, which means it won't be able to access the socket.
   * There are roughly three things that get in the way:
   * (1) Permissions of the socket.
   * (2) Permissions of the parent directory(-ies).  Remember this
   *     if $TMPDIR is located in your home directory.
   * (3) SELinux/sVirt will prevent access.  libvirt ought to
   *     label the socket.
   */
  if (is_root) {
    struct group *grp;

    if (chmod (guestfsd_sock, 0775) == -1) {
      perrorf (g, "chmod: %s", guestfsd_sock);
      goto cleanup;
    }

    if (chmod (console_sock, 0775) == -1) {
      perrorf (g, "chmod: %s", console_sock);
      goto cleanup;
    }

    grp = getgrnam ("qemu");
    if (grp != NULL) {
      if (chown (guestfsd_sock, 0, grp->gr_gid) == -1) {
        perrorf (g, "chown: %s", guestfsd_sock);
        goto cleanup;
      }
      if (chown (console_sock, 0, grp->gr_gid) == -1) {
        perrorf (g, "chown: %s", console_sock);
        goto cleanup;
      }
    } else
      debug (g, "cannot find group 'qemu'");
  }

  /* Construct the libvirt XML. */
  if (g->verbose)
    guestfs___print_timestamped_message (g, "create libvirt XML");

  xml = construct_libvirt_xml (g, capabilities,
                               kernel, initrd, appliance_overlay,
                               guestfsd_sock, console_sock,
                               disable_svirt);
  if (!xml)
    goto cleanup;

  /* Launch the libvirt guest. */
  if (g->verbose)
    guestfs___print_timestamped_message (g, "launch libvirt guest");

  dom = virDomainCreateXML (conn, (char *) xml, VIR_DOMAIN_START_AUTODESTROY);
  if (!dom) {
    libvirt_error (g, _("could not create appliance through libvirt"));
    goto cleanup;
  }

  g->state = LAUNCHING;

  /* Wait for console socket to open. */
  r = accept4 (console, NULL, NULL, SOCK_NONBLOCK|SOCK_CLOEXEC);
  if (r == -1) {
    perrorf (g, "accept");
    goto cleanup;
  }
  if (close (console) == -1) {
    perrorf (g, "close: console socket");
    close (r);
    goto cleanup;
  }
  g->fd[0] = r; /* This is the accepted console socket. */

  g->fd[1] = dup (g->fd[0]);
  if (g->fd[1] == -1) {
    perrorf (g, "dup");
    goto cleanup;
  }

  /* Wait for libvirt domain to start and to connect back to us via
   * virtio-serial and send the GUESTFS_LAUNCH_FLAG message.
   */
  r = guestfs___accept_from_daemon (g);
  if (r == -1)
    goto cleanup;

  /* NB: We reach here just because qemu has opened the socket.  It
   * does not mean the daemon is up until we read the
   * GUESTFS_LAUNCH_FLAG below.  Failures in qemu startup can still
   * happen even if we reach here, even early failures like not being
   * able to open a drive.
   */

  /* Close the listening socket. */
  if (close (g->sock) == -1) {
    perrorf (g, "close: listening socket");
    close (r);
    g->sock = -1;
    goto cleanup;
  }
  g->sock = r; /* This is the accepted data socket. */

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup;
  }

  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);

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

  guestfs___add_dummy_appliance_drive (g);

  TRACE0 (launch_libvirt_end);

  guestfs___launch_send_progress (g, 12);

  g->virt.connv = conn;
  g->virt.domv = dom;

  free (kernel);
  free (initrd);
  free (appliance);
  free (appliance_overlay);
  free (xml);
  free (capabilities);

  return 0;

 cleanup:
  if (console >= 0)
    close (console);
  if (g->fd[0] >= 0) {
    close (g->fd[0]);
    g->fd[0] = -1;
  }
  if (g->fd[1] >= 0) {
    close (g->fd[1]);
    g->fd[1] = -1;
  }
  if (g->sock >= 0) {
    close (g->sock);
    g->sock = -1;
  }

  if (dom) {
    virDomainDestroy (dom);
    virDomainFree (dom);
  }
  if (conn)
    virConnectClose (conn);

  free (kernel);
  free (initrd);
  free (appliance);
  free (appliance_overlay);
  free (capabilities);
  free (xml);

  g->state = CONFIG;

  return -1;
}

static int
is_custom_qemu (guestfs_h *g)
{
  return g->qemu && STRNEQ (g->qemu, QEMU);
}

static int construct_libvirt_xml_name (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_cpu (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_boot (guestfs_h *g, xmlTextWriterPtr xo, const char *kernel, const char *initrd, size_t appliance_index);
static int construct_libvirt_xml_seclabel (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_lifecycle (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_devices (guestfs_h *g, xmlTextWriterPtr xo, const char *appliance_overlay, size_t appliance_index, const char *guestfsd_sock, const char *console_sock);
static int construct_libvirt_xml_qemu_cmdline (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_disk (guestfs_h *g, xmlTextWriterPtr xo, struct drive *drv, size_t drv_index);
static int construct_libvirt_xml_appliance (guestfs_h *g, xmlTextWriterPtr xo, const char *appliance_overlay, size_t appliance_index);

#define XMLERROR(code,e) do {                                           \
    if ((e) == (code)) {                                                \
      perrorf (g, _("error constructing libvirt XML at \"%s\""),        \
               #e);                                                     \
      goto err;                                                         \
    }                                                                   \
  } while (0)

static xmlChar *
construct_libvirt_xml (guestfs_h *g, const char *capabilities_xml,
                       const char *kernel, const char *initrd,
                       const char *appliance_overlay,
                       const char *guestfsd_sock, const char *console_sock,
                       int disable_svirt)
{
  xmlChar *ret = NULL;
  xmlBufferPtr xb = NULL;
  xmlOutputBufferPtr ob;
  xmlTextWriterPtr xo = NULL;
  size_t appliance_index = g->nr_drives;
  const char *type;

  /* Big hack, instead of actually parsing the capabilities XML (XXX). */
  type = strstr (capabilities_xml, "'kvm'") != NULL ? "kvm" : "qemu";

  XMLERROR (NULL, xb = xmlBufferCreate ());
  XMLERROR (NULL, ob = xmlOutputBufferCreateBuffer (xb, NULL));
  XMLERROR (NULL, xo = xmlNewTextWriter (ob));

  XMLERROR (-1, xmlTextWriterSetIndent (xo, 1));
  XMLERROR (-1, xmlTextWriterSetIndentString (xo, BAD_CAST "  "));
  XMLERROR (-1, xmlTextWriterStartDocument (xo, NULL, NULL, NULL));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "domain"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type", BAD_CAST type));
  XMLERROR (-1,
            xmlTextWriterWriteAttributeNS (xo,
                                           BAD_CAST "xmlns",
                                           BAD_CAST "qemu",
                                           NULL,
                                           BAD_CAST "http://libvirt.org/schemas/domain/qemu/1.0"));

  if (construct_libvirt_xml_name (g, xo) == -1)
    goto err;
  if (construct_libvirt_xml_cpu (g, xo) == -1)
    goto err;
  if (construct_libvirt_xml_boot (g, xo, kernel, initrd, appliance_index) == -1)
    goto err;
  if (disable_svirt)
    if (construct_libvirt_xml_seclabel (g, xo) == -1)
      goto err;
  if (construct_libvirt_xml_lifecycle (g, xo) == -1)
    goto err;
  if (construct_libvirt_xml_devices (g, xo, appliance_overlay, appliance_index,
                                     guestfsd_sock, console_sock) == -1)
    goto err;
  if (construct_libvirt_xml_qemu_cmdline (g, xo) == -1)
    goto err;

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterEndDocument (xo));
  XMLERROR (NULL, ret = xmlBufferDetach (xb)); /* caller frees ret */

  debug (g, "libvirt XML:\n%s", ret);

 err:
  if (xo)
    xmlFreeTextWriter (xo); /* frees 'ob' too */
  if (xb)
    xmlBufferFree (xb);

  return ret;
}

/* Construct a securely random name.  We don't need to save the name
 * because if we ever needed it, it's available from libvirt.
 */
#define DOMAIN_NAME_LEN 16

static int
construct_libvirt_xml_name (guestfs_h *g, xmlTextWriterPtr xo)
{
  char name[DOMAIN_NAME_LEN+1];

  if (random_chars (name, DOMAIN_NAME_LEN) == -1) {
    perrorf (g, "/dev/urandom");
    goto err;
  }

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "name"));
  XMLERROR (-1, xmlTextWriterWriteFormatString (xo, "guestfs-%s", name));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

/* CPU and memory features. */
static int
construct_libvirt_xml_cpu (guestfs_h *g, xmlTextWriterPtr xo)
{
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "memory"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "unit", BAD_CAST "MiB"));
  XMLERROR (-1, xmlTextWriterWriteFormatString (xo, "%d", g->memsize));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "currentMemory"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "unit", BAD_CAST "MiB"));
  XMLERROR (-1, xmlTextWriterWriteFormatString (xo, "%d", g->memsize));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "cpu"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "model",
                                         BAD_CAST "host-model"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "vcpu"));
  XMLERROR (-1, xmlTextWriterWriteFormatString (xo, "%d", g->smp));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "clock"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "offset",
                                         BAD_CAST "utc"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

/* Boot parameters. */
static int
construct_libvirt_xml_boot (guestfs_h *g, xmlTextWriterPtr xo,
                            const char *kernel, const char *initrd,
                            size_t appliance_index)
{
  char buf[256];
  char appliance_root[64] = "";

  /* XXX Lots of common code shared with src/launch-appliance.c */
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
  guestfs___drive_name (appliance_index, appliance_root);

  snprintf (buf, sizeof buf,
            LINUX_CMDLINE
            "root=/dev/sd%s "   /* (root) */
            "%s "               /* (selinux) */
            "%s "               /* (verbose) */
            "TERM=%s "          /* (TERM environment variable) */
            "%s",               /* (append) */
            appliance_root,
            g->selinux ? "selinux=1 enforcing=0" : "selinux=0",
            g->verbose ? "guestfs_verbose=1" : "",
            getenv ("TERM") ? : "linux",
            g->append ? g->append : "");

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "os"));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "type"));
  XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST "hvm"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "kernel"));
  XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST kernel));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "initrd"));
  XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST initrd));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "cmdline"));
  XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST buf));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

static int
construct_libvirt_xml_seclabel (guestfs_h *g, xmlTextWriterPtr xo)
{
  /* This disables SELinux/sVirt confinement. */
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "seclabel"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "none"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

/* qemu -no-reboot */
static int
construct_libvirt_xml_lifecycle (guestfs_h *g, xmlTextWriterPtr xo)
{
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "on_reboot"));
  XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST "destroy"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

/* Devices. */
static int
construct_libvirt_xml_devices (guestfs_h *g, xmlTextWriterPtr xo,
                               const char *appliance_overlay,
                               size_t appliance_index,
                               const char *guestfsd_sock,
                               const char *console_sock)
{
  struct drive *drv;
  size_t i;

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "devices"));

  /* Path to qemu.  Only write this if the user has changed the
   * default, otherwise allow libvirt to choose the best one.
   */
  if (is_custom_qemu (g)) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "emulator"));
    XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST g->qemu));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  /* virtio-scsi controller. */
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "controller"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "scsi"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "index",
                                         BAD_CAST "0"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "model",
                                         BAD_CAST "virtio-scsi"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  /* Disks. */
  ITER_DRIVES (g, i, drv) {
    if (construct_libvirt_xml_disk (g, xo, drv, i) == -1)
      goto err;
  }

  /* Appliance disk. */
  if (construct_libvirt_xml_appliance (g, xo, appliance_overlay,
                                       appliance_index) == -1)
    goto err;

  /* Console. */
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "serial"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "unix"));
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "source"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "mode",
                                         BAD_CAST "connect"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "path",
                                         BAD_CAST console_sock));
  XMLERROR (-1, xmlTextWriterEndElement (xo));
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "target"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "port",
                                         BAD_CAST "0"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  /* Virtio-serial for guestfsd communication. */
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "channel"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "unix"));
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "source"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "mode",
                                         BAD_CAST "connect"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "path",
                                         BAD_CAST guestfsd_sock));
  XMLERROR (-1, xmlTextWriterEndElement (xo));
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "target"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "virtio"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "name",
                                         BAD_CAST "org.libguestfs.channel.0"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

static int
construct_libvirt_xml_disk (guestfs_h *g, xmlTextWriterPtr xo,
                            struct drive *drv, size_t drv_index)
{
  char drive_name[64] = "sd";
  char scsi_target[64];
  struct drive_libvirt *drv_priv;
  char *format = NULL;
  int is_host_device;

  /* XXX We probably could support this if we thought about it some more. */
  if (drv->iface) {
    error (g, _("'iface' parameter is not supported by the libvirt attach-method"));
    goto err;
  }

  guestfs___drive_name (drv_index, &drive_name[2]);
  snprintf (scsi_target, sizeof scsi_target, "%zu", drv_index);

  drv_priv = (struct drive_libvirt *) drv->priv;

  /* Change the libvirt XML according to whether the host path is
   * a device or a file.  For devices, use:
   *   <disk type=block device=disk>
   *     <source dev=[path]>
   * For files, use:
   *   <disk type=file device=disk>
   *     <source file=[path]>
   */
  is_host_device = is_blk (drv_priv->path);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "disk"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "device",
                                         BAD_CAST "disk"));
  if (!is_host_device) {
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                           BAD_CAST "file"));

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "source"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "file",
                                           BAD_CAST drv_priv->path));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }
  else {
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                           BAD_CAST "block"));

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "source"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "dev",
                                           BAD_CAST drv_priv->path));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "target"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "dev",
                                         BAD_CAST drive_name));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "bus",
                                         BAD_CAST "scsi"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "driver"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "name",
                                         BAD_CAST "qemu"));
  if (drv_priv->format) {
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                           BAD_CAST drv_priv->format));
  }
  else {
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
    format = guestfs_disk_format (g, drv_priv->path);
    if (!format)
      goto err;

    if (STREQ (format, "unknown")) {
      error (g, _("could not auto-detect the format of '%s'\n"
                  "If the format is known, pass the format to libguestfs, eg. using the\n"
                  "'--format' option, or via the optional 'format' argument to 'add-drive'."),
             drv->path);
      goto err;
    }

    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                           BAD_CAST format));
  }
  if (drv->use_cache_none) {
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "cache",
                                           BAD_CAST "none"));
  }
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  if (drv->disk_label) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "serial"));
    XMLERROR (-1, xmlTextWriterWriteString (xo, BAD_CAST drv->disk_label));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "address"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "drive"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "controller",
                                         BAD_CAST "0"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "bus",
                                         BAD_CAST "0"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "target",
                                         BAD_CAST scsi_target));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "unit",
                                         BAD_CAST "0"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  free (format);
  return 0;

 err:
  free (format);
  return -1;
}

static int
construct_libvirt_xml_appliance (guestfs_h *g, xmlTextWriterPtr xo,
                                 const char *appliance_overlay,
                                 size_t drv_index)
{
  char drive_name[64] = "sd";
  char scsi_target[64];

  guestfs___drive_name (drv_index, &drive_name[2]);
  snprintf (scsi_target, sizeof scsi_target, "%zu", drv_index);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "disk"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "file"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "device",
                                         BAD_CAST "disk"));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "source"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "file",
                                         BAD_CAST appliance_overlay));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "target"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "dev",
                                         BAD_CAST drive_name));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "bus",
                                         BAD_CAST "scsi"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "driver"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "name",
                                         BAD_CAST "qemu"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "qcow2"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "cache",
                                         BAD_CAST "unsafe"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "address"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "drive"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "controller",
                                         BAD_CAST "0"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "bus",
                                         BAD_CAST "0"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "target",
                                         BAD_CAST scsi_target));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "unit",
                                         BAD_CAST "0"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "shareable"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  /* We'd like to do this, but it's not supported by libvirt.
   * See construct_libvirt_xml_qemu_cmdline for the workaround.
   *
   * XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "transient"));
   * XMLERROR (-1, xmlTextWriterEndElement (xo));
   */

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

static int
construct_libvirt_xml_qemu_cmdline (guestfs_h *g, xmlTextWriterPtr xo)
{
  struct qemu_param *qp;
  char *p;

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:commandline"));

  /* We need to ensure the snapshots are created in $TMPDIR (RHBZ#856619). */
  p = getenv ("TMPDIR");
  if (p) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:env"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "name",
                                           BAD_CAST "TMPDIR"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST p));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  /* Workaround because libvirt user networking cannot specify "net="
   * parameter.
   */
  if (g->enable_network) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST "-netdev"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST "user,id=usernet,net=169.254.0.0/16"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST "-device"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST "virtio-net-pci,netdev=usernet"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  /* The qemu command line arguments requested by the caller. */
  for (qp = g->qemu_params; qp; qp = qp->next) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST qp->qemu_param));
    XMLERROR (-1, xmlTextWriterEndElement (xo));

    if (qp->qemu_value) {
      XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
      XMLERROR (-1,
                xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                             BAD_CAST qp->qemu_value));
      XMLERROR (-1, xmlTextWriterEndElement (xo));
    }
  }

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

static int
is_blk (const char *path)
{
  struct stat statbuf;

  if (stat (path, &statbuf) == -1)
    return 0;
  return S_ISBLK (statbuf.st_mode);
}

static int
random_chars (char *ret, size_t len)
{
  int fd;
  size_t i;
  unsigned char c;
  int saved_errno;

  fd = open ("/dev/urandom", O_RDONLY|O_CLOEXEC);
  if (fd == -1)
    return -1;

  for (i = 0; i < len; ++i) {
    if (read (fd, &c, 1) != 1) {
      saved_errno = errno;
      close (fd);
      errno = saved_errno;
      return -1;
    }
    ret[i] = "0123456789abcdefghijklmnopqrstuvwxyz"[c % 36];
  }
  ret[len] = '\0';

  if (close (fd) == -1)
    return -1;

  return 0;
}

static void
ignore_errors (void *ignore, virErrorPtr ignore2)
{
  /* empty */
}

/* Create a temporary qcow2 overlay on top of 'path'. */
static char *
make_qcow2_overlay (guestfs_h *g, const char *path, const char *format)
{
  char *tmpfile = NULL;
  int fd[2] = { -1, -1 };
  pid_t pid = -1;
  FILE *fp = NULL;
  char *line = NULL;
  size_t len;
  int r;

  /* Path must be absolute. */
  assert (path);
  assert (path[0] == '/');

  tmpfile = safe_asprintf (g, "%s/snapshot%d", g->tmpdir, ++g->unique);

  /* Because 'qemu-img create' spews junk to stdout and stderr, pass
   * all output from it up through the event system.
   * XXX Like libvirt, we should create a generic library for running
   * commands.
   */
  if (pipe2 (fd, O_CLOEXEC) == -1) {
    perrorf (g, "pipe2");
    goto error;
  }

  pid = fork ();
  if (pid == -1) {
    perrorf (g, "fork");
    goto error;
  }

  if (pid == 0) {               /* child: qemu-img create command */
    /* Capture stdout and stderr. */
    close (fd[0]);
    dup2 (fd[1], 1);
    dup2 (fd[1], 2);
    close (fd[1]);

    setenv ("LC_ALL", "C", 1);

    if (!format)
      execlp ("qemu-img", "qemu-img", "create", "-f", "qcow2",
              "-b", path, tmpfile, NULL);
    else {
      size_t len = strlen (format);
      char backing_fmt[len+64];

      snprintf (backing_fmt, len+64, "backing_fmt=%s", format);

      execlp ("qemu-img", "qemu-img", "create", "-f", "qcow2",
              "-b", path, "-o", backing_fmt, tmpfile, NULL);
    }

    perror ("could not execute 'qemu-img create' command");
    _exit (EXIT_FAILURE);
  }

  close (fd[1]);
  fd[1] = -1;

  fp = fdopen (fd[0], "r");
  if (fp == NULL) {
    perrorf (g, "fdopen: qemu-img create");
    goto error;
  }
  fd[0] = -1;

  while (getline (&line, &len, fp) != -1) {
    guestfs___call_callbacks_message (g, GUESTFS_EVENT_LIBRARY, line, len);
  }

  if (fclose (fp) == -1) { /* also closes fd[0] */
    perrorf (g, "fclose");
    fp = NULL;
    goto error;
  }
  fp = NULL;

  free (line);
  line = NULL;

  if (waitpid (pid, &r, 0) == -1) {
    perrorf (g, "waitpid");
    pid = 0;
    goto error;
  }
  pid = 0;

  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    error (g, _("qemu-img create: could not create snapshot over %s"), path);
    goto error;
  }

  return tmpfile;               /* caller frees */

 error:
  if (fd[0] >= 0)
    close (fd[0]);
  if (fd[1] >= 0)
    close (fd[1]);
  if (fp != NULL)
    fclose (fp);
  if (pid > 0)
    waitpid (pid, NULL, 0);

  free (tmpfile);
  free (line);

  return NULL;
}

static int
make_qcow2_overlay_for_drive (guestfs_h *g, struct drive *drv)
{
  char *path;
  struct drive_libvirt *drv_priv;

  if (drv->priv && drv->free_priv)
    drv->free_priv (drv->priv);

  drv->priv = drv_priv = safe_calloc (g, 1, sizeof (struct drive_libvirt));
  drv->free_priv = drive_free_priv;

  /* Even for non-readonly paths, we need to make the paths absolute here. */
  path = realpath (drv->path, NULL);
  if (path == NULL) {
    perrorf (g, _("realpath: could not convert '%s' to absolute path"),
             drv->path);
    return -1;
  }

  if (!drv->readonly) {
    drv_priv->path = path;
    drv_priv->format = drv->format ? safe_strdup (g, drv->format) : NULL;
  }
  else {
    drv_priv->path = make_qcow2_overlay (g, path, drv->format);
    free (path);
    if (!drv_priv->path)
      return -1;
    drv_priv->format = safe_strdup (g, "qcow2");
  }

  return 0;
}

static void
drive_free_priv (void *priv)
{
  struct drive_libvirt *drv_priv = priv;

  free (drv_priv->path);
  free (drv_priv->format);
  free (drv_priv);
}

static int
shutdown_libvirt (guestfs_h *g, int check_for_errors)
{
  virConnectPtr conn = g->virt.connv;
  virDomainPtr dom = g->virt.domv;
  int ret = 0;
  int flags;

  /* Note that we can be called back very early in launch (specifically
   * from launch_libvirt itself), when conn and dom might be NULL.
   */

  if (dom != NULL) {
    flags = check_for_errors ? VIR_DOMAIN_DESTROY_GRACEFUL : 0;
    if (virDomainDestroyFlags (dom, flags) == -1) {
      libvirt_error (g, _("could not destroy libvirt domain"));
      ret = -1;
    }
    virDomainFree (dom);
  }

  if (conn != NULL)
    virConnectClose (conn);

  g->virt.connv = g->virt.domv = NULL;

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

/* This backend assumes virtio-scsi is available. */
static int
max_disks_libvirt (guestfs_h *g)
{
  return 255;
}

#else /* no libvirt or libxml2 at compile time */

#define NOT_IMPL(r)                                                     \
  error (g, _("libvirt attach-method is not available because "         \
              "this version of libguestfs was compiled "                \
              "without libvirt or libvirt < %d.%d.%d or without libxml2"), \
         MIN_LIBVIRT_MAJOR, MIN_LIBVIRT_MINOR, MIN_LIBVIRT_MICRO);      \
  return r

static int
launch_libvirt (guestfs_h *g, const char *arg)
{
  NOT_IMPL (-1);
}

static int
shutdown_libvirt (guestfs_h *g, int check_for_errors)
{
  NOT_IMPL (-1);
}

static int
max_disks_libvirt (guestfs_h *g)
{
  NOT_IMPL (-1);
}

#endif /* no libvirt or libxml2 at compile time */

struct attach_ops attach_ops_libvirt = {
  .launch = launch_libvirt,
  .shutdown = shutdown_libvirt,
  .max_disks = max_disks_libvirt,
};
