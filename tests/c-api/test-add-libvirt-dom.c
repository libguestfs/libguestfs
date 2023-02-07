/* libguestfs
 * Copyright (C) 2010-2023 Red Hat Inc.
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

#include "guestfs.h"
#include "guestfs-utils.h"

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
  char cwd[1024];
  FILE *fp;
  char libvirt_uri[sizeof cwd + 64];

  if (getcwd (cwd, sizeof cwd) == NULL)
    error (EXIT_FAILURE, errno, "getcwd");

  /* Create the guestfs handle. */
  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

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
    error (EXIT_FAILURE, 0,
           "could not connect to libvirt (code %d, domain %d): %s",
           err->code, err->domain, err->message);
  }

  dom = virDomainLookupByName (conn, "guest");
  if (!dom) {
    err = virGetLastError ();
    error (EXIT_FAILURE, 0,
           "no libvirt domain called '%s': %s", "guest", err->message);
  }

  r = guestfs_add_libvirt_dom (g, dom,
                               GUESTFS_ADD_LIBVIRT_DOM_READONLY, 1,
                               -1);
  if (r == -1)
    exit (EXIT_FAILURE);

  if (r != 3)
    error (EXIT_FAILURE, 0,
           "incorrect number of disks added (%d, expected 3)", r);

  guestfs_close (g);

  virDomainFree (dom);
  virConnectClose (conn);

  unlink ("test-add-libvirt-dom.xml");
  unlink ("test-add-libvirt-dom-1.img");
  unlink ("test-add-libvirt-dom-2.img");
  unlink ("test-add-libvirt-dom-3.img");

  exit (EXIT_SUCCESS);
}
