/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>

#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>

#include "fish.h"

static int add_drives_from_node_set (xmlDocPtr doc, xmlNodeSetPtr nodes);

/* Implements the guts of the '-d' option.
 *
 * Note that we have to observe the '--ro' flag in two respects: by
 * adding the drives read-only if the flag is set, and by restricting
 * guests to shut down ones unless '--ro' is set.
 *
 * Returns the number of drives added (> 0), or -1 for failure.
 */
int
add_libvirt_drives (const char *guest)
{
  static int initialized = 0;
  if (!initialized) {
    initialized = 1;

    if (virInitialize () == -1)
      return -1;

    xmlInitParser ();
    LIBXML_TEST_VERSION;
  }

  int r = -1, nr_added = 0;
  virErrorPtr err;
  virConnectPtr conn = NULL;
  virDomainPtr dom = NULL;
  xmlDocPtr doc = NULL;
  xmlXPathContextPtr xpathCtx = NULL;
  xmlXPathObjectPtr xpathObj = NULL;
  char *xml = NULL;

  /* Connect to libvirt, find the domain. */
  conn = virConnectOpenReadOnly (libvirt_uri);
  if (!conn) {
    err = virGetLastError ();
    fprintf (stderr, _("guestfish: could not connect to libvirt (code %d, domain %d): %s\n"),
             err->code, err->domain, err->message);
    goto cleanup;
  }

  dom = virDomainLookupByName (conn, guest);
  if (!dom) {
    err = virConnGetLastError (conn);
    fprintf (stderr, _("guestfish: no libvirt domain called '%s': %s\n"),
             guest, err->message);
    goto cleanup;
  }
  if (!read_only) {
    virDomainInfo info;
    if (virDomainGetInfo (dom, &info) == -1) {
      err = virConnGetLastError (conn);
      fprintf (stderr, _("guestfish: error getting domain info about '%s': %s\n"),
               guest, err->message);
      goto cleanup;
    }
    if (info.state != VIR_DOMAIN_SHUTOFF) {
      fprintf (stderr, _("guestfish: error: '%s' is a live virtual machine.\nYou must use '--ro' because write access to a running virtual machine can\ncause disk corruption.\n"),
               guest);
      goto cleanup;
    }
  }

  /* Domain XML. */
  xml = virDomainGetXMLDesc (dom, 0);

  if (!xml) {
    err = virConnGetLastError (conn);
    fprintf (stderr, _("guestfish: error reading libvirt XML information about '%s': %s\n"),
             guest, err->message);
    goto cleanup;
  }

  /* Now the horrible task of parsing out the fields we need from the XML.
   * http://www.xmlsoft.org/examples/xpath1.c
   */
  doc = xmlParseMemory (xml, strlen (xml));
  if (doc == NULL) {
    fprintf (stderr, _("guestfish: unable to parse XML information returned by libvirt\n"));
    goto cleanup;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    fprintf (stderr, _("guestfish: unable to create new XPath context\n"));
    goto cleanup;
  }

  xpathObj = xmlXPathEvalExpression (BAD_CAST "//devices/disk/source/@dev",
                                     xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("guestfish: unable to evaluate XPath expression\n"));
    goto cleanup;
  }

  nr_added += add_drives_from_node_set (doc, xpathObj->nodesetval);

  xmlXPathFreeObject (xpathObj); xpathObj = NULL;

  xpathObj = xmlXPathEvalExpression (BAD_CAST "//devices/disk/source/@file",
                                     xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("guestfish: unable to evaluate XPath expression\n"));
    goto cleanup;
  }

  nr_added += add_drives_from_node_set (doc, xpathObj->nodesetval);

  if (nr_added == 0) {
    fprintf (stderr, _("guestfish: libvirt domain '%s' has no disks\n"),
             guest);
    goto cleanup;
  }

  /* Successful. */
  r = nr_added;

cleanup:
  free (xml);
  if (xpathObj) xmlXPathFreeObject (xpathObj);
  if (xpathCtx) xmlXPathFreeContext (xpathCtx);
  if (doc) xmlFreeDoc (doc);
  if (dom) virDomainFree (dom);
  if (conn) virConnectClose (conn);

  return r;
}

static int
add_drives_from_node_set (xmlDocPtr doc, xmlNodeSetPtr nodes)
{
  if (!nodes)
    return 0;

  int i;

  for (i = 0; i < nodes->nodeNr; ++i) {
    assert (nodes->nodeTab[i]);
    assert (nodes->nodeTab[i]->type == XML_ATTRIBUTE_NODE);
    xmlAttrPtr attr = (xmlAttrPtr) nodes->nodeTab[i];

    char *device = (char *) xmlNodeListGetString (doc, attr->children, 1);

    int r;
    if (!read_only)
      r = guestfs_add_drive (g, device);
    else
      r = guestfs_add_drive_ro (g, device);
    if (r == -1)
      exit (EXIT_FAILURE);

    xmlFree (device);
  }

  return nodes->nodeNr;
}
