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

/* To do (XXX):
 *
 * - Need to query libvirt to find out if virtio-scsi is supported.
 *   This code assumes it.
 *
 * - SELinux labelling of guestfsd.sock, console.sock
 *
 * - Set qemu binary to non-standard (g->qemu).
 *
 * - Check for feature parity with src/launch-appliance.c
 *
 * - Environment variable $LIBGUESTFS_ATTACH_METHOD
 *
 * - ./configure override default
 *
 * - Remote support.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
#include <grp.h>
#include <assert.h>
#include <sys/stat.h>

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

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)

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

static xmlChar *construct_libvirt_xml (guestfs_h *g, const char *capabilities_xml, const char *kernel, const char *initrd, const char *appliance, const char *guestfsd_sock, const char *console_sock);

static void libvirt_error (guestfs_h *g, const char *fs, ...);

static int
launch_libvirt (guestfs_h *g, const char *libvirt_uri)
{
  unsigned long version;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  char *capabilities = NULL;
  xmlChar *xml = NULL;
  char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  char guestfsd_sock[256];
  struct sockaddr_un addr;
  char console_sock[256];
  int console = -1, r;

  /* At present you must add drives before starting the appliance.  In
   * future when we enable hotplugging you won't need to do this.
   */
  if (!g->drives) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  /* Check minimum required version of libvirt.  The libvirt backend
   * is new and not the default, so we can get away with forcing
   * people who want to try it to have a reasonably new version of
   * libvirt, so we don't have to work around any bugs in libvirt.
   */
  virGetVersion (&version, NULL, NULL);
  debug (g, "libvirt version = %lu", version);
  if (version < 9013) {
    error (g, _("you need a newer version of libvirt to use the 'libvirt' attach-method"));
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
    error (g, _("could not connect to libvirt: URI: %s"),
           libvirt_uri ? : "NULL");
    goto cleanup;
  }

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
   * (3) SELinux/sVirt will prevent access.
   */
  if (geteuid () == 0) {
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
                               kernel, initrd, appliance,
                               guestfsd_sock, console_sock);
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

  free (kernel);
  kernel = NULL;
  free (initrd);
  initrd = NULL;
  free (appliance);
  appliance = NULL;
  free (xml);
  xml = NULL;
  free (capabilities);
  capabilities = NULL;

  g->state = LAUNCHING;

  /* Wait for console socket to open. */
  r = accept (console, NULL, NULL);
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

  if (fcntl (g->fd[0], F_SETFL, O_NONBLOCK|O_CLOEXEC) == -1) {
    perrorf (g, "fcntl");
    goto cleanup;
  }
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

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK|O_CLOEXEC) == -1) {
    perrorf (g, "fcntl");
    goto cleanup;
  }

  uint32_t size;
  void *buf = NULL;
  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) {
    error (g, _("guestfs_launch failed, see earlier error messages"));
    goto cleanup;
  }

  if (size != GUESTFS_LAUNCH_FLAG) {
    error (g, _("guestfs_launch failed, see earlier error messages"));
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

  TRACE0 (launch_libvirt_end);

  guestfs___launch_send_progress (g, 12);

  g->virt.connv = conn;
  g->virt.domv = dom;

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
  g->state = CONFIG;
  free (kernel);
  free (initrd);
  free (appliance);
  free (capabilities);
  free (xml);
  if (dom) {
    virDomainDestroy (dom);
    virDomainFree (dom);
  }
  if (conn)
    virConnectClose (conn);

  return -1;
}

static int construct_libvirt_xml_name (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_cpu (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_boot (guestfs_h *g, xmlTextWriterPtr xo, const char *kernel, const char *initrd, size_t appliance_index);
static int construct_libvirt_xml_seclabel (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_devices (guestfs_h *g, xmlTextWriterPtr xo, const char *appliance, size_t appliance_index, const char *guestfsd_sock, const char *console_sock);
static int construct_libvirt_xml_qemu_cmdline (guestfs_h *g, xmlTextWriterPtr xo);
static int construct_libvirt_xml_disk (guestfs_h *g, xmlTextWriterPtr xo, struct drive *drv, size_t drv_index);
static int construct_libvirt_xml_appliance (guestfs_h *g, xmlTextWriterPtr xo, const char *appliance, size_t appliance_index);

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
                       const char *appliance,
                       const char *guestfsd_sock, const char *console_sock)
{
  xmlChar *ret = NULL;
  xmlBufferPtr xb = NULL;
  xmlOutputBufferPtr ob;
  xmlTextWriterPtr xo = NULL;
  struct drive *drv = g->drives;
  size_t appliance_index = 0;

  /* Count the number of disks added, in order to get the offset
   * of the appliance disk.
   */
  while (drv != NULL) {
    drv = drv->next;
    appliance_index++;
  }

  XMLERROR (NULL, xb = xmlBufferCreate ());
  XMLERROR (NULL, ob = xmlOutputBufferCreateBuffer (xb, NULL));
  XMLERROR (NULL, xo = xmlNewTextWriter (ob));

  XMLERROR (-1, xmlTextWriterSetIndent (xo, 1));
  XMLERROR (-1, xmlTextWriterSetIndentString (xo, BAD_CAST "  "));
  XMLERROR (-1, xmlTextWriterStartDocument (xo, NULL, NULL, NULL));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "domain"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type", BAD_CAST "kvm"));
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
  if (construct_libvirt_xml_seclabel (g, xo) == -1)
    goto err;
  if (construct_libvirt_xml_devices (g, xo, appliance, appliance_index,
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
  int fd;
  char name[DOMAIN_NAME_LEN+1];
  size_t i;
  unsigned char c;

  fd = open ("/dev/urandom", O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "/dev/urandom: open");
    return -1;
  }

  for (i = 0; i < DOMAIN_NAME_LEN; ++i) {
    if (read (fd, &c, 1) != 1) {
      perrorf (g, "/dev/urandom: read");
      close (fd);
      return -1;
    }
    name[i] = "0123456789abcdefghijklmnopqrstuvwxyz"[c % 36];
  }
  name[DOMAIN_NAME_LEN] = '\0';

  close (fd);

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
  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "seclabel"));
  /* XXX This disables SELinux/sVirt confinement.  Remove this
   * once we've worked out how to label guestfsd_sock.
   */
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "type",
                                         BAD_CAST "none"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

/* Devices. */
static int
construct_libvirt_xml_devices (guestfs_h *g, xmlTextWriterPtr xo,
                               const char *appliance, size_t appliance_index,
                               const char *guestfsd_sock,
                               const char *console_sock)
{
  struct drive *drv = g->drives;
  size_t drv_index = 0;

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "devices"));

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
  while (drv != NULL) {
    if (construct_libvirt_xml_disk (g, xo, drv, drv_index) == -1)
      goto err;
    drv = drv->next;
    drv_index++;
  }

  /* Appliance disk. */
  if (construct_libvirt_xml_appliance (g, xo, appliance, appliance_index) == -1)
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
  char *path = NULL;

  guestfs___drive_name (drv_index, &drive_name[2]);
  snprintf (scsi_target, sizeof scsi_target, "%zu", drv_index);

  /* Drive path must be absolute for libvirt. */
  path = realpath (drv->path, NULL);
  if (path == NULL) {
    perrorf (g, "realpath: could not convert '%s' to absolute path", drv->path);
    goto err;
  }

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
                                         BAD_CAST path));
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
  if (drv->format) {
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "format",
                                           BAD_CAST drv->format));
  }
  if (drv->use_cache_none) {
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "cache",
                                           BAD_CAST "none"));
  }
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

  /* We'd like to do this, but it's not supported by libvirt.
   * See construct_libvirt_xml_qemu_cmdline for the workaround.
   *
   * if (drv->readonly) {
   *   XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "transient"));
   *   XMLERROR (-1, xmlTextWriterEndElement (xo));
   * }
   */

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  free (path);
  return 0;

 err:
  free (path);
  return -1;
}

static int
construct_libvirt_xml_appliance (guestfs_h *g, xmlTextWriterPtr xo,
                                 const char *appliance, size_t drv_index)
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
                                         BAD_CAST appliance));
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
            xmlTextWriterWriteAttribute (xo, BAD_CAST "format",
                                         BAD_CAST "raw"));
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
  struct drive *drv;
  size_t drv_index;
  char attr[256];
  struct qemu_param *qp;

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:commandline"));

  /* Workaround because libvirt can't do snapshot=on yet.  Idea inspired
   * by Stefan Hajnoczi's post here:
   * http://blog.vmsplice.net/2011/04/how-to-pass-qemu-command-line-options.html
   */
  for (drv = g->drives, drv_index = 0; drv; drv = drv->next, drv_index++) {
    if (drv->readonly) {
      snprintf (attr, sizeof attr,
                "drive.drive-scsi0-0-%zu-0.snapshot=on", drv_index);

      XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
      XMLERROR (-1,
                xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                             BAD_CAST "-set"));
      XMLERROR (-1, xmlTextWriterEndElement (xo));

      XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
      XMLERROR (-1,
                xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                             BAD_CAST attr));
      XMLERROR (-1, xmlTextWriterEndElement (xo));
    }
  }

  snprintf (attr, sizeof attr,
            "drive.drive-scsi0-0-%zu-0.snapshot=on", drv_index);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                         BAD_CAST "-set"));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
  XMLERROR (-1,
            xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                         BAD_CAST attr));
  XMLERROR (-1, xmlTextWriterEndElement (xo));

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

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "qemu:arg"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "value",
                                           BAD_CAST qp->qemu_value));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  XMLERROR (-1, xmlTextWriterEndElement (xo));

  return 0;

 err:
  return -1;
}

static int
shutdown_libvirt (guestfs_h *g)
{
  virConnectPtr conn = g->virt.connv;
  virDomainPtr dom = g->virt.domv;
  int ret = 0;

  assert (conn != NULL);
  assert (dom != NULL);

  /* XXX Need to be graceful? */
  if (virDomainDestroyFlags (dom, 0) == -1) {
    libvirt_error (g, _("could not destroy libvirt domain"));
    ret = -1;
  }
  virDomainFree (dom);
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

  error (g, "%s: %s [code=%d domain=%d]",
         msg, err->message, err->code, err->domain);

  /* NB. 'err' must not be freed! */
  free (msg);
}

#else /* no libvirt or libxml2 at compile time */

#define NOT_IMPL(r)                                                     \
  error (g, _("libvirt attach-method is not available since this version of libguestfs was compiled without libvirt or libxml2")); \
  return r

static int
launch_libvirt (guestfs_h *g, const char *arg)
{
  NOT_IMPL (-1);
}

static int
shutdown_libvirt (guestfs_h *g)
{
  NOT_IMPL (-1);
}

#endif /* no libvirt or libxml2 at compile time */

struct attach_ops attach_ops_libvirt = {
  .launch = launch_libvirt,
  .shutdown = shutdown_libvirt,
};
