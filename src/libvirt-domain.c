/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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
#include <assert.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#ifdef HAVE_LIBXML2
#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)

static void
ignore_errors (void *ignore, virErrorPtr ignore2)
{
  /* empty */
}

struct guestfs___add_libvirt_dom_argv {
  uint64_t bitmask;
#define GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK (UINT64_C(1)<<0)
  int readonly;
#define GUESTFS___ADD_LIBVIRT_DOM_IFACE_BITMASK (UINT64_C(1)<<1)
  const char *iface;
#define GUESTFS___ADD_LIBVIRT_DOM_LIVE_BITMASK (UINT64_C(1)<<2)
  int live;
#define GUESTFS___ADD_LIBVIRT_DOM_READONLYDISK_BITMASK (UINT64_C(1)<<3)
  const char *readonlydisk;
};

static int guestfs___add_libvirt_dom (guestfs_h *g, virDomainPtr dom, const struct guestfs___add_libvirt_dom_argv *optargs);

int
guestfs__add_domain (guestfs_h *g, const char *domain_name,
                     const struct guestfs_add_domain_argv *optargs)
{
  virErrorPtr err;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  int r = -1;
  const char *libvirturi;
  int readonly;
  int live;
  int allowuuid;
  const char *readonlydisk;
  const char *iface;
  struct guestfs___add_libvirt_dom_argv optargs2 = { .bitmask = 0 };

  libvirturi = optargs->bitmask & GUESTFS_ADD_DOMAIN_LIBVIRTURI_BITMASK
               ? optargs->libvirturi : NULL;
  readonly = optargs->bitmask & GUESTFS_ADD_DOMAIN_READONLY_BITMASK
             ? optargs->readonly : 0;
  iface = optargs->bitmask & GUESTFS_ADD_DOMAIN_IFACE_BITMASK
          ? optargs->iface : NULL;
  live = optargs->bitmask & GUESTFS_ADD_DOMAIN_LIVE_BITMASK
         ? optargs->live : 0;
  allowuuid = optargs->bitmask & GUESTFS_ADD_DOMAIN_ALLOWUUID_BITMASK
            ? optargs->allowuuid : 0;
  readonlydisk = optargs->bitmask & GUESTFS_ADD_DOMAIN_READONLYDISK_BITMASK
               ? optargs->readonlydisk : NULL;

  if (live && readonly) {
    error (g, _("you cannot set both live and readonly flags"));
    return -1;
  }

  /* Connect to libvirt, find the domain. */
  conn = guestfs___open_libvirt_connection (g, libvirturi, VIR_CONNECT_RO);
  if (!conn) {
    err = virGetLastError ();
    error (g, _("could not connect to libvirt (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
    goto cleanup;
  }

  /* Suppress default behaviour of printing errors to stderr.  Note
   * you can't set this to NULL to ignore errors; setting it to NULL
   * restores the default error handler ...
   */
  virConnSetErrorFunc (conn, NULL, ignore_errors);

  /* Try UUID first. */
  if (allowuuid)
    dom = virDomainLookupByUUIDString (conn, domain_name);

  /* Try ordinary domain name. */
  if (!dom)
    dom = virDomainLookupByName (conn, domain_name);

  if (!dom) {
    err = virGetLastError ();
    error (g, _("no libvirt domain called '%s': %s"),
           domain_name, err->message);
    goto cleanup;
  }

  if (readonly) {
    optargs2.bitmask |= GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK;
    optargs2.readonly = readonly;
  }
  if (iface) {
    optargs2.bitmask |= GUESTFS___ADD_LIBVIRT_DOM_IFACE_BITMASK;
    optargs2.iface = iface;
  }
  if (live) {
    optargs2.bitmask |= GUESTFS___ADD_LIBVIRT_DOM_LIVE_BITMASK;
    optargs2.live = live;
  }
  if (readonlydisk) {
    optargs2.bitmask |= GUESTFS___ADD_LIBVIRT_DOM_READONLYDISK_BITMASK;
    optargs2.readonlydisk = readonlydisk;
  }

  r = guestfs___add_libvirt_dom (g, dom, &optargs2);

 cleanup:
  if (dom) virDomainFree (dom);
  if (conn) virConnectClose (conn);

  return r;
}

/* This was proposed as an external API, but it's not quite baked yet. */

static int add_disk (guestfs_h *g, const char *filename, const char *format, int readonly, void *data);
static int connect_live (guestfs_h *g, virDomainPtr dom);

enum readonlydisk {
  readonlydisk_error,
  readonlydisk_read,
  readonlydisk_write,
  readonlydisk_ignore,
};

struct add_disk_data {
  int readonly;
  enum readonlydisk readonlydisk;
  /* Other args to pass through to add_drive_opts. */
  struct guestfs_add_drive_opts_argv optargs;
};

static int
guestfs___add_libvirt_dom (guestfs_h *g, virDomainPtr dom,
                           const struct guestfs___add_libvirt_dom_argv *optargs)
{
  int r;
  int readonly;
  const char *iface;
  int live;
  /* Default for back-compat reasons: */
  enum readonlydisk readonlydisk = readonlydisk_write;

  readonly =
    optargs->bitmask & GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK
    ? optargs->readonly : 0;
  iface =
    optargs->bitmask & GUESTFS___ADD_LIBVIRT_DOM_IFACE_BITMASK
    ? optargs->iface : NULL;
  live =
    optargs->bitmask & GUESTFS___ADD_LIBVIRT_DOM_LIVE_BITMASK
    ? optargs->live : 0;

  if ((optargs->bitmask & GUESTFS___ADD_LIBVIRT_DOM_READONLYDISK_BITMASK)) {
    if (STREQ (optargs->readonlydisk, "error"))
      readonlydisk = readonlydisk_error;
    else if (STREQ (optargs->readonlydisk, "read"))
      readonlydisk = readonlydisk_read;
    else if (STREQ (optargs->readonlydisk, "write"))
      readonlydisk = readonlydisk_write;
    else if (STREQ (optargs->readonlydisk, "ignore"))
      readonlydisk = readonlydisk_ignore;
    else {
      error (g, _("unknown readonlydisk parameter"));
      return -1;
    }
  }

  if (live && readonly) {
    error (g, _("you cannot set both live and readonly flags"));
    return -1;
  }

  if (!readonly) {
    virDomainInfo info;
    virErrorPtr err;
    int vm_running;

    if (virDomainGetInfo (dom, &info) == -1) {
      err = virGetLastError ();
      error (g, _("error getting domain info: %s"), err->message);
      return -1;
    }
    vm_running = info.state != VIR_DOMAIN_SHUTOFF;

    if (vm_running) {
      /* If the caller specified the 'live' flag, then they want us to
       * try to connect to guestfsd if the domain is running.  Note
       * that live readonly connections are not possible.
       */
      if (live)
        return connect_live (g, dom);

      /* Dangerous to modify the disks of a running VM. */
      error (g, _("error: domain is a live virtual machine.\n"
                  "Writing to the disks of a running virtual machine can cause disk corruption.\n"
                  "Either use read-only access, or if the guest is running the guestfsd daemon\n"
                  "specify live access.  In most libguestfs tools these options are --ro or\n"
                  "--live respectively.  Consult the documentation for further information."));
      return -1;
    }
  }

  /* Add the disks. */
  struct add_disk_data data;
  data.optargs.bitmask = 0;
  data.readonly = readonly;
  data.readonlydisk = readonlydisk;
  if (iface) {
    data.optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK;
    data.optargs.iface = iface;
  }

  /* Checkpoint the command line around the operation so that either
   * all disks are added or none are added.
   */
  size_t cp = guestfs___checkpoint_drives (g);
  r = guestfs___for_each_disk (g, dom, add_disk, &data, guestfs___error_errno);
  if (r == -1)
    guestfs___rollback_drives (g, cp);

  return r;
}

static int
add_disk (guestfs_h *g,
          const char *filename, const char *format, int readonly_in_xml,
          void *datavp)
{
  struct add_disk_data *data = datavp;
  /* Copy whole struct so we can make local changes: */
  struct guestfs_add_drive_opts_argv optargs = data->optargs;
  int readonly, error = 0, skip = 0;

  if (readonly_in_xml) {        /* <readonly/> appears in the XML */
    if (data->readonly) {       /* asked to add disk read-only */
      switch (data->readonlydisk) {
      case readonlydisk_error: readonly = 1; break;
      case readonlydisk_read: readonly = 1; break;
      case readonlydisk_write: readonly = 1; break;
      case readonlydisk_ignore: skip = 1; break;
      default: abort ();
      }
    } else {                    /* asked to add disk for read/write */
      switch (data->readonlydisk) {
      case readonlydisk_error: error = 1; break;
      case readonlydisk_read: readonly = 1; break;
      case readonlydisk_write: readonly = 0; break;
      case readonlydisk_ignore: skip = 1; break;
      default: abort ();
      }
    }
  } else                        /* no <readonly/> in XML */
    readonly = data->readonly;

  if (skip)
    return 0;

  if (error) {
    error (g, _("%s: disk is marked <readonly/> in libvirt XML, and readonlydisk was set to \"error\""),
           filename);
    return -1;
  }

  optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK;
  optargs.readonly = readonly;

  if (format) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
    optargs.format = format;
  }

  return guestfs__add_drive_opts (g, filename, &optargs);
}

static int
connect_live (guestfs_h *g, virDomainPtr dom)
{
  int i;
  virErrorPtr err;
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  CLEANUP_FREE char *xml = NULL, *path = NULL, *attach_method = NULL;
  xmlNodeSetPtr nodes;

  /* Domain XML. */
  xml = virDomainGetXMLDesc (dom, 0);

  if (!xml) {
    err = virGetLastError ();
    error (g, _("error reading libvirt XML information: %s"),
           err->message);
    return -1;
  }

  /* Parse XML to document. */
  doc = xmlParseMemory (xml, strlen (xml));
  if (doc == NULL) {
    error (g, _("unable to parse XML information returned by libvirt"));
    return -1;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    return -1;
  }

  /* This gives us a set of all the <channel> nodes related to the
   * guestfsd virtio-serial channel.
   */
  xpathObj = xmlXPathEvalExpression (BAD_CAST
      "//devices/channel[@type=\"unix\" and "
                        "./source/@mode=\"bind\" and "
                        "./source/@path and "
                        "./target/@type=\"virtio\" and "
                        "./target/@name=\"org.libguestfs.channel.0\"]",
                                     xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression"));
    return -1;
  }

  nodes = xpathObj->nodesetval;
  for (i = 0; i < nodes->nodeNr; ++i) {
    CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xppath = NULL;
    xmlAttrPtr attr;

    /* See note in function above. */
    xpathCtx->node = nodes->nodeTab[i];

    /* The path is in <source path=..> attribute. */
    xppath = xmlXPathEvalExpression (BAD_CAST "./source/@path", xpathCtx);
    if (xppath == NULL ||
        xppath->nodesetval == NULL ||
        xppath->nodesetval->nodeNr == 0) {
      xmlXPathFreeObject (xppath);
      continue;                 /* no type attribute, skip it */
    }
    assert (xppath->nodesetval->nodeTab[0]);
    assert (xppath->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
    attr = (xmlAttrPtr) xppath->nodesetval->nodeTab[0];
    path = (char *) xmlNodeListGetString (doc, attr->children, 1);
    break;
  }

  if (path == NULL) {
    error (g, _("this guest has no libvirt <channel> definition for guestfsd\n"
                "See ATTACHING TO RUNNING DAEMONS in guestfs(3) for further information."));
    return -1;
  }

  /* Got a path. */
  attach_method = safe_asprintf (g, "unix:%s", path);
  return guestfs_set_attach_method (g, attach_method);
}

#else /* no libvirt or libxml2 at compile time */

#define NOT_IMPL(r)                                                     \
  error (g, _("add-domain API not available since this version of libguestfs was compiled without libvirt or libxml2")); \
  return r

int
guestfs__add_domain (guestfs_h *g, const char *dom,
                     const struct guestfs_add_domain_argv *optargs)
{
  NOT_IMPL(-1);
}

#endif /* no libvirt or libxml2 at compile time */
