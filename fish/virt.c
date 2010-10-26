/* libguestfs - guestfish and guestmount shared option parsing
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

#include "guestfs.h"

#include "options.h"

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

  int r = -1, nr_added = 0, i;
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
    fprintf (stderr, _("%s: could not connect to libvirt (code %d, domain %d): %s\n"),
             program_name, err->code, err->domain, err->message);
    goto cleanup;
  }

  dom = virDomainLookupByName (conn, guest);
  if (!dom) {
    err = virConnGetLastError (conn);
    fprintf (stderr, _("%s: no libvirt domain called '%s': %s\n"),
             program_name, guest, err->message);
    goto cleanup;
  }
  if (!read_only) {
    virDomainInfo info;
    if (virDomainGetInfo (dom, &info) == -1) {
      err = virConnGetLastError (conn);
      fprintf (stderr, _("%s: error getting domain info about '%s': %s\n"),
               program_name, guest, err->message);
      goto cleanup;
    }
    if (info.state != VIR_DOMAIN_SHUTOFF) {
      fprintf (stderr, _("%s: error: '%s' is a live virtual machine.\nYou must use '--ro' because write access to a running virtual machine can\ncause disk corruption.\n"),
               program_name, guest);
      goto cleanup;
    }
  }

  /* Domain XML. */
  xml = virDomainGetXMLDesc (dom, 0);

  if (!xml) {
    err = virConnGetLastError (conn);
    fprintf (stderr, _("%s: error reading libvirt XML information about '%s': %s\n"),
             program_name, guest, err->message);
    goto cleanup;
  }

  /* Now the horrible task of parsing out the fields we need from the XML.
   * http://www.xmlsoft.org/examples/xpath1.c
   */
  doc = xmlParseMemory (xml, strlen (xml));
  if (doc == NULL) {
    fprintf (stderr, _("%s: unable to parse XML information returned by libvirt\n"),
             program_name);
    goto cleanup;
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    fprintf (stderr, _("%s: unable to create new XPath context\n"),
             program_name);
    goto cleanup;
  }

  /* This gives us a set of all the <disk> nodes. */
  xpathObj = xmlXPathEvalExpression (BAD_CAST "//devices/disk", xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("%s: unable to evaluate XPath expression\n"),
             program_name);
    goto cleanup;
  }

  xmlNodeSetPtr nodes = xpathObj->nodesetval;
  for (i = 0; i < nodes->nodeNr; ++i) {
    xmlXPathObjectPtr xpfilename;
    xmlXPathObjectPtr xpformat;

    /* Change the context to the current <disk> node.
     * DV advises to reset this before each search since older versions of
     * libxml2 might overwrite it.
     */
    xpathCtx->node = nodes->nodeTab[i];

    /* Filename can be in <source dev=..> or <source file=..> attribute. */
    xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@dev", xpathCtx);
    if (xpfilename == NULL ||
        xpfilename->nodesetval == NULL ||
        xpfilename->nodesetval->nodeNr == 0) {
      xmlXPathFreeObject (xpfilename);
      xpathCtx->node = nodes->nodeTab[i];
      xpfilename = xmlXPathEvalExpression (BAD_CAST "./source/@file", xpathCtx);
      if (xpfilename == NULL ||
          xpfilename->nodesetval == NULL ||
          xpfilename->nodesetval->nodeNr == 0) {
        xmlXPathFreeObject (xpfilename);
        continue;               /* disk filename not found, skip this */
      }
    }

    assert (xpfilename->nodesetval->nodeTab[0]);
    assert (xpfilename->nodesetval->nodeTab[0]->type == XML_ATTRIBUTE_NODE);
    xmlAttrPtr attr = (xmlAttrPtr) xpfilename->nodesetval->nodeTab[0];
    char *filename = (char *) xmlNodeListGetString (doc, attr->children, 1);

    /* Get the disk format (may not be set). */
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

    /* Add the disk, with optional format. */
    struct guestfs_add_drive_opts_argv optargs = { .bitmask = 0 };
    if (read_only) {
      optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK;
      optargs.readonly = read_only;
    }
    if (format) {
      optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
      optargs.format = format;
    }

    int t = guestfs_add_drive_opts_argv (g, filename, &optargs);

    xmlFree (filename);
    xmlFree (format);
    xmlXPathFreeObject (xpfilename);
    xmlXPathFreeObject (xpformat);

    if (t == -1)
      goto cleanup;

    nr_added++;
  }

  if (nr_added == 0) {
    fprintf (stderr, _("%s: libvirt domain '%s' has no disks\n"),
             program_name, guest);
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
