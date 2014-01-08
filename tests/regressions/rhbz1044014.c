/* libguestfs
 * Copyright (C) 2014 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Regression test for RHBZ#1044014.
 *
 * The only reason to write this in C is so we can easily check the
 * version of libvirt >= 1.2.1.  In the future when we can assume a
 * newer libvirt, we can just have the main rhbz1044014.sh script set
 * some environment variables and use guestfish.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include <libvirt/libvirt.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

int
main (int argc, char *argv[])
{
  unsigned long ver;
  guestfs_h *g;

  virInitialize ();

  /* Check that the version of libvirt we are linked against
   * supports the new test-driver auth feature.
   */
  virGetVersion (&ver, NULL, NULL);
  if (ver < 1002001) {
    fprintf (stderr, "%s: test skipped because libvirt is too old (%lu)\n",
             argv[0], ver);
    exit (77);
  }

  g = guestfs_create ();
  if (!g)
    exit (EXIT_FAILURE);

  /* This will ask the user for credentials.  It will also fail
   * (expectedly) because the test driver does not support qemu/KVM.
   */
  guestfs_launch (g);

  guestfs_close (g);
  exit (EXIT_SUCCESS);
}
