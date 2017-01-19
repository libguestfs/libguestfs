/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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

/**
 * Libguestfs uses C<CLEANUP_*> macros to simplify temporary
 * allocations.  They are implemented using the
 * C<__attribute__((cleanup))> feature of gcc and clang.  Typical
 * usage is:
 *
 *  fn ()
 *  {
 *    CLEANUP_FREE char *str = NULL;
 *    str = safe_asprintf (g, "foo");
 *    // str is freed automatically when the function returns
 *  }
 *
 * There are a few catches to be aware of with the cleanup mechanism:
 *
 * =over 4
 *
 * =item *
 *
 * If a cleanup variable is not initialized, then you can end up
 * calling L<free(3)> with an undefined value, resulting in the
 * program crashing.  For this reason, you should usually initialize
 * every cleanup variable with something, eg. C<NULL>
 *
 * =item *
 *
 * Don't mark variables holding return values as cleanup variables.
 *
 * =item *
 *
 * The C<main()> function shouldn't use cleanup variables since it is
 * normally exited by calling L<exit(3)>, and that doesn't call the
 * cleanup handlers.
 *
 * =back
 *
 * The functions in this file are used internally by the C<CLEANUP_*>
 * macros.  Don't call them directly.
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

#include "hash.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

void
guestfs_int_cleanup_free (void *ptr)
{
  free (* (void **) ptr);
}

void
guestfs_int_cleanup_free_string_list (char ***ptr)
{
  guestfs_int_free_string_list (*ptr);
}

void
guestfs_int_cleanup_hash_free (void *ptr)
{
  Hash_table *h = * (Hash_table **) ptr;

  if (h)
    hash_free (h);
}

void
guestfs_int_cleanup_unlink_free (char **ptr)
{
  char *filename = *ptr;

  if (filename) {
    unlink (filename);
    free (filename);
  }
}

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

void
guestfs_int_cleanup_fclose (void *ptr)
{
  FILE *f = * (FILE **) ptr;

  if (f)
    fclose (f);
}

void
guestfs_int_cleanup_pclose (void *ptr)
{
  FILE *f = * (FILE **) ptr;

  if (f)
    pclose (f);
}
