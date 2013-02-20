/* libguestfs
 * Copyright (C) 2010-2013 Red Hat Inc.
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

static void default_error_function (guestfs_h *g, int errnum, const char *fs, ...) __attribute__((format (printf,3,4)));

/* This function is also used in tools code (virt-df and others) to
 * avoid having all that stupid XPath code repeated.  This is
 * something that libvirt should really provide.
 *
 * The callback function 'f' is called once for each disk.
 *
 * The error function can be NULL, in which case errors are printed on
 * stderr (usually fine for tools).  Or in the library you can pass in
 * guestfs___error_errno.
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
                         void *data,
                         error_function_t error_function)
{
  int i, nr_added = 0;
  virErrorPtr err;
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  CLEANUP_FREE char *xml = NULL;
  xmlNodeSetPtr nodes;

  if (!error_function)
    error_function = default_error_function;

  /* Domain XML. */
  xml = virDomainGetXMLDesc (dom, 0);

  if (!xml) {
    err = virGetLastError ();
    error_function (g, 0, _("error reading libvirt XML information: %s"),
                    err->message);
    return -1;
  }

  /* Now the horrible task of parsing out the fields we need from the XML.
   * http://www.xmlsoft.org/examples/xpath1.c
   */
  doc = xmlParseMemory (xml, strlen (xml));
  if (doc == NULL) {
    error_function (g, 0,
                    _("unable to parse XML information returned by libvirt"));
    return -1;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    error_function (g, 0, _("unable to create new XPath context"));
    return -1;
  }

  /* This gives us a set of all the <disk> nodes. */
  xpathObj = xmlXPathEvalExpression (BAD_CAST "//devices/disk", xpathCtx);
  if (xpathObj == NULL) {
    error_function (g, 0, _("unable to evaluate XPath expression"));
    return -1;
  }

  nodes = xpathObj->nodesetval;
  for (i = 0; i < nodes->nodeNr; ++i) {
    CLEANUP_FREE char *type = NULL, *filename = NULL, *format = NULL;
    CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xptype = NULL;
    CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpformat = NULL;
    CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpreadonly = NULL;
    CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpfilename = NULL;
    xmlAttrPtr attr;
    int readonly;
    int t;

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
      continue;                 /* no type attribute, skip it */
    }
    assert (xptype->nodesetval->nodeTab[0]);
    assert (xptype->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
    attr = (xmlAttrPtr) xptype->nodesetval->nodeTab[0];
    type = (char *) xmlNodeListGetString (doc, attr->children, 1);

    if (STREQ (type, "file")) { /* type = "file" so look at source/@file */
      xpathCtx->node = nodes->nodeTab[i];
      xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@file", xpathCtx);
      if (xpfilename == NULL ||
          xpfilename->nodesetval == NULL ||
          xpfilename->nodesetval->nodeNr == 0) {
        continue;             /* disk filename not found, skip this */
      }
    } else if (STREQ (type, "block")) { /* type = "block", use source/@dev */
      xpathCtx->node = nodes->nodeTab[i];
      xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@dev", xpathCtx);
      if (xpfilename == NULL ||
          xpfilename->nodesetval == NULL ||
          xpfilename->nodesetval->nodeNr == 0) {
        continue;             /* disk filename not found, skip this */
      }
    } else
      continue;               /* type <> "file" or "block", skip it */

    assert (xpfilename);
    assert (xpfilename->nodesetval);
    assert (xpfilename->nodesetval->nodeTab[0]);
    assert (xpfilename->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
    attr = (xmlAttrPtr) xpfilename->nodesetval->nodeTab[0];
    filename = (char *) xmlNodeListGetString (doc, attr->children, 1);

    /* Get the disk format (may not be set). */
    xpathCtx->node = nodes->nodeTab[i];
    xpformat = xmlXPathEvalExpression (BAD_CAST "./driver/@type", xpathCtx);
    if (xpformat != NULL &&
        xpformat->nodesetval &&
        xpformat->nodesetval->nodeNr > 0) {
      assert (xpformat->nodesetval->nodeTab[0]);
      assert (xpformat->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
      attr = (xmlAttrPtr) xpformat->nodesetval->nodeTab[0];
      format = (char *) xmlNodeListGetString (doc, attr->children, 1);
    }

    /* Get the <readonly/> flag. */
    xpathCtx->node = nodes->nodeTab[i];
    xpreadonly = xmlXPathEvalExpression (BAD_CAST "./readonly", xpathCtx);
    readonly = 0;
    if (xpreadonly != NULL &&
        xpreadonly->nodesetval &&
        xpreadonly->nodesetval->nodeNr > 0)
      readonly = 1;

    if (f)
      t = f (g, filename, format, readonly, data);
    else
      t = 0;

    if (t == -1)
      return -1;

    nr_added++;
  }

  if (nr_added == 0) {
    error_function (g, 0, _("libvirt domain has no disks"));
    return -1;
  }

  /* Successful. */
  return nr_added;
}

static void
default_error_function (guestfs_h *g, int errnum, const char *fs, ...)
{
  va_list args;

  va_start (args, fs);
  vfprintf (stderr, fs, args);
  va_end (args);

  if (errnum != 0)
    fprintf (stderr, "%s", strerror (errnum));

  fprintf (stderr, "\n");
}

#endif /* no libvirt or libxml2 at compile time */
