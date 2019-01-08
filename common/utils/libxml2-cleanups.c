/* libguestfs
 * Copyright (C) 2013-2019 Red Hat Inc.
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
#include <unistd.h>
#include <string.h>

#include <libxml/uri.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xmlwriter.h>

#include "cleanups.h"

void
guestfs_int_cleanup_xmlFree (void *ptr)
{
  xmlChar *buf = * (xmlChar **) ptr;

  if (buf)
    xmlFree (buf);
}

void
guestfs_int_cleanup_xmlBufferFree (void *ptr)
{
  xmlBufferPtr xb = * (xmlBufferPtr *) ptr;

  if (xb)
    xmlBufferFree (xb);
}

void
guestfs_int_cleanup_xmlFreeDoc (void *ptr)
{
  xmlDocPtr doc = * (xmlDocPtr *) ptr;

  if (doc)
    xmlFreeDoc (doc);
}

void
guestfs_int_cleanup_xmlFreeURI (void *ptr)
{
  xmlURIPtr uri = * (xmlURIPtr *) ptr;

  if (uri)
    xmlFreeURI (uri);
}

void
guestfs_int_cleanup_xmlFreeTextWriter (void *ptr)
{
  xmlTextWriterPtr xo = * (xmlTextWriterPtr *) ptr;

  if (xo)
    xmlFreeTextWriter (xo);
}

void
guestfs_int_cleanup_xmlXPathFreeContext (void *ptr)
{
  xmlXPathContextPtr ctx = * (xmlXPathContextPtr *) ptr;

  if (ctx)
    xmlXPathFreeContext (ctx);
}

void
guestfs_int_cleanup_xmlXPathFreeObject (void *ptr)
{
  xmlXPathObjectPtr obj = * (xmlXPathObjectPtr *) ptr;

  if (obj)
    xmlXPathFreeObject (obj);
}
