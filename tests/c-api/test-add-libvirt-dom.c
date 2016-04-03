/* libguestfs
 * Copyright (C) 2010-2016 Red Hat Inc.
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
#include <errno.h>
#include <error.h>

#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>

#include "xgetcwd.h"

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
  char *backend;
  char *cwd;
  FILE *fp;
  char libvirt_uri[1024];

  cwd = xgetcwd ();

  /* Create the guestfs handle. */
  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "failed to create handle\n");
    exit (EXIT_FAILURE);
  }

  backend = guestfs_get_backend (g);
  if (STREQ (backend, "uml")) {
    printf ("%s: test skipped because UML backend does not support qcow2\n",
            argv[0]);
    free (backend);
    exit (77);
  }
  free (backend);

  /* Create the libvirt XML and test images in the current
   * directory.
   */
  fp = fopen ("test-add-libvirt-dom.xml", "w");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "fopen: %s", "test-add-libvirt-dom.xml");
  make_test_xml (fp, cwd);
  fclose (fp);

  if (guestfs_disk_create (g, "test-add-libvirt-dom-1.img", "raw",
                           1024*1024, -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_disk_create (g, "test-add-libvirt-dom-2.img", "raw",
                           1024*1024, -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_disk_create (g, "test-add-libvirt-dom-3.img", "qcow2",
                           1024*1024, -1) == -1)
    exit (EXIT_FAILURE);

  /* Create the libvirt connection. */
  snprintf (libvirt_uri, sizeof libvirt_uri,
            "test://%s/test-add-libvirt-dom.xml", cwd);
  conn = virConnectOpenReadOnly (libvirt_uri);
  if (!conn) {
    err = virGetLastError ();
    fprintf (stderr,
             "%s: could not connect to libvirt (code %d, domain %d): %s\n",
             argv[0], err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  dom = virDomainLookupByName (conn, "guest");
  if (!dom) {
    err = virGetLastError ();
    fprintf (stderr,
             "%s: no libvirt domain called '%s': %s\n",
             argv[0], "guest", err->message);
    exit (EXIT_FAILURE);
  }

  r = guestfs_add_libvirt_dom (g, dom,
                               GUESTFS_ADD_LIBVIRT_DOM_READONLY, 1,
                               -1);
  if (r == -1)
    exit (EXIT_FAILURE);

  if (r != 3) {
    fprintf (stderr,
             "%s: incorrect number of disks added (%d, expected 3)\n",
             argv[0], r);
    exit (EXIT_FAILURE);
  }

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
