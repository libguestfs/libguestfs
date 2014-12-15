/* libguestfs
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "xgetcwd.h"

#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

static void
make_test_xml (FILE *fp, const char *cwd)
{
  fprintf (fp,
           "<?xml version=\"1.0\"?>\n"
           "<node>\n"
           "  <domain type='test'>\n"
           "    <name>guest</name>\n"
           "    <os>\n"
           "      <type>hvm</type>\n"
           "      <boot dev='hd'/>\n"
           "    </os>\n"
           "    <memory>524288</memory>\n"
           "    <devices>\n"
           "      <disk type='file'>\n"
           "        <source file='%s/test-add-libvirt-dom-1.img'/>\n"
           "        <target dev='hda'/>\n"
           "      </disk>\n"
           "      <disk type='file'>\n"
           "        <driver name='qemu' type='raw'/>\n"
           "        <source file='%s/test-add-libvirt-dom-2.img'/>\n"
           "        <target dev='hdb'/>\n"
           "      </disk>\n"
           "      <disk type='file'>\n"
           "        <driver name='qemu' type='qcow2'/>\n"
           "        <source file='%s/test-add-libvirt-dom-3.img'/>\n"
           "        <target dev='hdc'/>\n"
           "      </disk>\n"
           "    </devices>\n"
           "  </domain>\n"
           "</node>",
           cwd, cwd, cwd);
}

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  virConnectPtr conn;
  virDomainPtr dom;
  virErrorPtr err;
  int r;
  const char *test_xml;
  char *cwd;
  FILE *fp;
  char libvirt_uri[1024];

  cwd = xgetcwd ();

  /* Create the libvirt XML and test images in the current
   * directory.
   */
  fp = fopen ("test-add-libvirt-dom.xml", "w");
  if (fp == NULL) {
    perror ("test-add-libvirt-dom.xml");
    exit (EXIT_FAILURE);
  }
  make_test_xml (fp, cwd);
  fclose (fp);

  fp = fopen ("test-add-libvirt-dom-1.img", "w");
  if (fp == NULL) {
    perror ("test-add-libvirt-dom-1.img");
    exit (EXIT_FAILURE);
  }
  fclose (fp);

  fp = fopen ("test-add-libvirt-dom-2.img", "w");
  if (fp == NULL) {
    perror ("test-add-libvirt-dom-2.img");
    exit (EXIT_FAILURE);
  }
  fclose (fp);

  fp = fopen ("test-add-libvirt-dom-3.img", "w");
  if (fp == NULL) {
    perror ("test-add-libvirt-dom-3.img");
    exit (EXIT_FAILURE);
  }
  fclose (fp);

  /* Create the guestfs handle. */
  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  /* Create the libvirt connection. */
  snprintf (libvirt_uri, sizeof libvirt_uri,
            "test://%s/test-add-libvirt-dom.xml", cwd);
  conn = virConnectOpenReadOnly (libvirt_uri);
  if (!conn) {
    err = virGetLastError ();
    fprintf (stderr, "could not connect to libvirt (code %d, domain %d): %s\n",
             err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  dom = virDomainLookupByName (conn, "guest");
  if (!dom) {
    err = virGetLastError ();
    fprintf (stderr,
             "no libvirt domain called '%s': %s\n", "guest", err->message);
    exit (EXIT_FAILURE);
  }

  r = guestfs_add_libvirt_dom (g, dom,
                               GUESTFS_ADD_LIBVIRT_DOM_READONLY, 1,
                               -1);
  if (r == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  virDomainFree (dom);
  virConnectClose (conn);
  free (cwd);

  unlink ("test-add-libvirt-dom.xml");
  unlink ("test-add-libvirt-dom-1.img");
  unlink ("test-add-libvirt-dom-2.img");
  unlink ("test-add-libvirt-dom-3.img");

  exit (EXIT_SUCCESS);
}
