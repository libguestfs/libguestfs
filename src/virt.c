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

#define GUESTFS_PRIVATE_FOR_EACH_DISK 1

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

struct guestfs___add_libvirt_dom_argv {
  uint64_t bitmask;
#define GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK (UINT64_C(1)<<0)
  int readonly;
#define GUESTFS___ADD_LIBVIRT_DOM_IFACE_BITMASK (UINT64_C(1)<<1)
  const char *iface;
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
  const char *iface;
  struct guestfs___add_libvirt_dom_argv optargs2 = { .bitmask = 0 };

  libvirturi = optargs->bitmask & GUESTFS_ADD_DOMAIN_LIBVIRTURI_BITMASK
               ? optargs->libvirturi : NULL;
  readonly = optargs->bitmask & GUESTFS_ADD_DOMAIN_READONLY_BITMASK
             ? optargs->readonly : 0;
  iface = optargs->bitmask & GUESTFS_ADD_DOMAIN_IFACE_BITMASK
          ? optargs->iface : NULL;

  /* Connect to libvirt, find the domain. */
  conn = virConnectOpenReadOnly (libvirturi);
  if (!conn) {
    err = virGetLastError ();
    error (g, _("could not connect to libvirt (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
    goto cleanup;
  }

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

    int t;
    if (f)
      t = f (g, filename, format, data);
    else
      t = 0;

    xmlFree (filename);
    xmlFree (format);
    xmlXPathFreeObject (xpfilename);
    xmlXPathFreeObject (xpformat);

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

static int
add_disk (guestfs_h *g, const char *filename, const char *format,
          void *optargs_vp)
{
  struct guestfs_add_drive_opts_argv *optargs = optargs_vp;

  if (format) {
    optargs->bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
    optargs->format = format;
  } else
    optargs->bitmask &= ~GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;

  return guestfs__add_drive_opts (g, filename, optargs);
}

/* This was proposed as an external API, but it's not quite baked yet. */
static int
guestfs___add_libvirt_dom (guestfs_h *g, virDomainPtr dom,
                           const struct guestfs___add_libvirt_dom_argv *optargs)
{
  int r = -1;
  virErrorPtr err;
  int cmdline_pos;

  cmdline_pos = guestfs___checkpoint_cmdline (g);

  int readonly =
    optargs->bitmask & GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK
    ? optargs->readonly : 0;
  const char *iface =
    optargs->bitmask & GUESTFS___ADD_LIBVIRT_DOM_IFACE_BITMASK
    ? optargs->iface : NULL;

  if (!readonly) {
    virDomainInfo info;
    if (virDomainGetInfo (dom, &info) == -1) {
      err = virGetLastError ();
      error (g, _("error getting domain info: %s"), err->message);
      goto cleanup;
    }
    if (info.state != VIR_DOMAIN_SHUTOFF) {
      error (g, _("error: domain is a live virtual machine.\nYou must use readonly access because write access to a running virtual machine\ncan cause disk corruption."));
      goto cleanup;
    }
  }

  /* Add the disks. */
  struct guestfs_add_drive_opts_argv optargs2 = { .bitmask = 0 };
  if (readonly) {
    optargs2.bitmask |= GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK;
    optargs2.readonly = readonly;
  }
  if (iface) {
    optargs2.bitmask |= GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK;
    optargs2.iface = iface;
  }

  r = guestfs___for_each_disk (g, dom, add_disk, &optargs2);

 cleanup:
  if (r == -1) guestfs___rollback_cmdline (g, cmdline_pos);
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
