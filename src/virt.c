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

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)
#define GUESTFS_PRIVATE_FOR_EACH_DISK 1
#endif

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)

static void init_libxml2 (void) __attribute__((constructor));

static void
init_libxml2 (void)
{
  /* I am told that you don't really need to call virInitialize ... */

  xmlInitParser ();
  LIBXML_TEST_VERSION;
}

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
  conn = virConnectOpenReadOnly (libvirturi);
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

/* This function is also used in virt-df to avoid having all that
 * stupid XPath code repeated.  This is something that libvirt should
 * really provide.
 *
 * The callback function 'f' is called once for each disk.
 *
 * Returns number of disks, or -1 if there was an error.
 */
int
guestfs___for_each_disk (guestfs_h *g,
                         virDomainPtr dom,
                         int (*f) (guestfs_h *g,
                                   const char *filename, const char *format,
                                   int readonly,
                                   void *data),
                         void *data)
{
  int i, nr_added = 0, r = -1;
  virErrorPtr err;
  xmlDocPtr doc = NULL;
  xmlXPathContextPtr xpathCtx = NULL;
  xmlXPathObjectPtr xpathObj = NULL;
  char *xml = NULL;

  /* Domain XML. */
  xml = virDomainGetXMLDesc (dom, 0);

  if (!xml) {
    err = virGetLastError ();
    error (g, _("error reading libvirt XML information: %s"),
           err->message);
    goto cleanup;
  }

  /* Now the horrible task of parsing out the fields we need from the XML.
   * http://www.xmlsoft.org/examples/xpath1.c
   */
  doc = xmlParseMemory (xml, strlen (xml));
  if (doc == NULL) {
    error (g, _("unable to parse XML information returned by libvirt"));
    goto cleanup;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    goto cleanup;
  }

  /* This gives us a set of all the <disk> nodes. */
  xpathObj = xmlXPathEvalExpression (BAD_CAST "//devices/disk", xpathCtx);
  if (xpathObj == NULL) {
    error (g, _("unable to evaluate XPath expression"));
    goto cleanup;
  }

  xmlNodeSetPtr nodes = xpathObj->nodesetval;
  for (i = 0; i < nodes->nodeNr; ++i) {
    xmlXPathObjectPtr xptype;

    /* Change the context to the current <disk> node.
     * DV advises to reset this before each search since older versions of
     * libxml2 might overwrite it.
     */
    xpathCtx->node = nodes->nodeTab[i];

    /* Filename can be in <source dev=..> or <source file=..> attribute.
     * Check the <disk type=..> attribute first to find out which one.
     */
    xptype = xmlXPathEvalExpression (BAD_CAST "./@type", xpathCtx);
    if (xptype == NULL ||
        xptype->nodesetval == NULL ||
        xptype->nodesetval->nodeNr == 0) {
      xmlXPathFreeObject (xptype);
      continue;                 /* no type attribute, skip it */
    }
    assert (xptype->nodesetval->nodeTab[0]);
    assert (xptype->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
    xmlAttrPtr attr = (xmlAttrPtr) xptype->nodesetval->nodeTab[0];
    char *type = (char *) xmlNodeListGetString (doc, attr->children, 1);
    xmlXPathFreeObject (xptype);

    xmlXPathObjectPtr xpfilename;

    if (STREQ (type, "file")) { /* type = "file" so look at source/@file */
      free (type);

      xpathCtx->node = nodes->nodeTab[i];
      xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@file", xpathCtx);
      if (xpfilename == NULL ||
          xpfilename->nodesetval == NULL ||
          xpfilename->nodesetval->nodeNr == 0) {
        xmlXPathFreeObject (xpfilename);
        continue;             /* disk filename not found, skip this */
      }
    } else if (STREQ (type, "block")) { /* type = "block", use source/@dev */
      free (type);

      xpathCtx->node = nodes->nodeTab[i];
      xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@dev", xpathCtx);
      if (xpfilename == NULL ||
          xpfilename->nodesetval == NULL ||
          xpfilename->nodesetval->nodeNr == 0) {
        xmlXPathFreeObject (xpfilename);
        continue;             /* disk filename not found, skip this */
      }
    } else {
      free (type);
      continue;               /* type <> "file" or "block", skip it */
    }

    assert (xpfilename->nodesetval->nodeTab[0]);
    assert (xpfilename->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
    attr = (xmlAttrPtr) xpfilename->nodesetval->nodeTab[0];
    char *filename = (char *) xmlNodeListGetString (doc, attr->children, 1);

    /* Get the disk format (may not be set). */
    xmlXPathObjectPtr xpformat;

    xpathCtx->node = nodes->nodeTab[i];
    xpformat = xmlXPathEvalExpression (BAD_CAST "./driver/@type", xpathCtx);
    char *format = NULL;
    if (xpformat != NULL &&
        xpformat->nodesetval &&
        xpformat->nodesetval->nodeNr > 0) {
      assert (xpformat->nodesetval->nodeTab[0]);
      assert (xpformat->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
      attr = (xmlAttrPtr) xpformat->nodesetval->nodeTab[0];
      format = (char *) xmlNodeListGetString (doc, attr->children, 1);
    }

    /* Get the <readonly/> flag. */
    xmlXPathObjectPtr xpreadonly;

    xpathCtx->node = nodes->nodeTab[i];
    xpreadonly = xmlXPathEvalExpression (BAD_CAST "./readonly", xpathCtx);
    int readonly = 0;
    if (xpreadonly != NULL &&
        xpreadonly->nodesetval &&
        xpreadonly->nodesetval->nodeNr > 0)
      readonly = 1;

    int t;
    if (f)
      t = f (g, filename, format, readonly, data);
    else
      t = 0;

    xmlFree (filename);
    xmlFree (format);
    xmlXPathFreeObject (xpfilename);
    xmlXPathFreeObject (xpformat);
    xmlXPathFreeObject (xpreadonly);

    if (t == -1)
      goto cleanup;

    nr_added++;
  }

  if (nr_added == 0) {
    error (g, _("libvirt domain has no disks"));
    goto cleanup;
  }

  /* Successful. */
  r = nr_added;

 cleanup:
  free (xml);
  if (xpathObj) xmlXPathFreeObject (xpathObj);
  if (xpathCtx) xmlXPathFreeContext (xpathCtx);
  if (doc) xmlFreeDoc (doc);

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
  struct drive **cp = guestfs___checkpoint_drives (g);
  r = guestfs___for_each_disk (g, dom, add_disk, &data);
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
  int i, r = -1;
  virErrorPtr err;
  xmlDocPtr doc = NULL;
  xmlXPathContextPtr xpathCtx = NULL;
  xmlXPathObjectPtr xpathObj = NULL;
  char *xml = NULL;
  char *path = NULL;
  char *attach_method = NULL;

  /* Domain XML. */
  xml = virDomainGetXMLDesc (dom, 0);

  if (!xml) {
    err = virGetLastError ();
    error (g, _("error reading libvirt XML information: %s"),
           err->message);
    goto cleanup;
  }

  /* Parse XML to document. */
  doc = xmlParseMemory (xml, strlen (xml));
  if (doc == NULL) {
    error (g, _("unable to parse XML information returned by libvirt"));
    goto cleanup;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error (g, _("unable to create new XPath context"));
    goto cleanup;
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
    goto cleanup;
  }

  xmlNodeSetPtr nodes = xpathObj->nodesetval;
  for (i = 0; i < nodes->nodeNr; ++i) {
    xmlXPathObjectPtr xppath;

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
    xmlAttrPtr attr = (xmlAttrPtr) xppath->nodesetval->nodeTab[0];
    path = (char *) xmlNodeListGetString (doc, attr->children, 1);
    xmlXPathFreeObject (xppath);
    break;
  }

  if (path == NULL) {
    error (g, _("this guest has no libvirt <channel> definition for guestfsd\n"
                "See ATTACHING TO RUNNING DAEMONS in guestfs(3) for further information."));
    goto cleanup;
  }

  /* Got a path. */
  attach_method = safe_malloc (g, strlen (path) + 5 + 1);
  strcpy (attach_method, "unix:");
  strcat (attach_method, path);
  r = guestfs_set_attach_method (g, attach_method);

 cleanup:
  free (path);
  free (attach_method);
  free (xml);
  if (xpathObj) xmlXPathFreeObject (xpathObj);
  if (xpathCtx) xmlXPathFreeContext (xpathCtx);
  if (doc) xmlFreeDoc (doc);

  return r;
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
