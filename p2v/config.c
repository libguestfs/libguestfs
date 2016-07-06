/* virt-p2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <locale.h>
#include <libintl.h>

#include "p2v.h"

struct config *
new_config (void)
{
  struct config *c;

  c = calloc (1, sizeof *c);
  if (c == NULL) {
    perror ("calloc");
    exit (EXIT_FAILURE);
  }

  c->port = 22;

  c->output_allocation = OUTPUT_ALLOCATION_NONE;

  return c;
}

struct config *
copy_config (struct config *old)
{
  struct config *c = new_config ();

  memcpy (c, old, sizeof *c);

  /* Need to deep copy strings and string lists. */
  if (c->server)
    c->server = strdup (c->server);
  if (c->username)
    c->username = strdup (c->username);
  if (c->password)
    c->password = strdup (c->password);
  if (c->identity_url)
    c->identity_url = strdup (c->identity_url);
  if (c->identity_file)
    c->identity_file = strdup (c->identity_file);
  if (c->guestname)
    c->guestname = strdup (c->guestname);
  if (c->disks)
    c->disks = guestfs_int_copy_string_list (c->disks);
  if (c->removable)
    c->removable = guestfs_int_copy_string_list (c->removable);
  if (c->interfaces)
    c->interfaces = guestfs_int_copy_string_list (c->interfaces);
  if (c->network_map)
    c->network_map = guestfs_int_copy_string_list (c->network_map);
  if (c->output)
    c->output = strdup (c->output);
  if (c->output_connection)
    c->output_connection = strdup (c->output_connection);
  if (c->output_format)
    c->output_format = strdup (c->output_format);
  if (c->output_storage)
    c->output_storage = strdup (c->output_storage);

  return c;
}

void
free_config (struct config *c)
{
  free (c->server);
  free (c->username);
  free (c->password);
  free (c->identity_url);
  free (c->identity_file);
  free (c->guestname);
  guestfs_int_free_string_list (c->disks);
  guestfs_int_free_string_list (c->removable);
  guestfs_int_free_string_list (c->interfaces);
  guestfs_int_free_string_list (c->network_map);
  free (c->output);
  free (c->output_connection);
  free (c->output_format);
  free (c->output_storage);
  free (c);
}

/* Print the conversion parameters and other important information. */
void
print_config (struct config *config, FILE *fp)
{
  size_t i;

  fprintf (fp, "local version   .  %s\n", PACKAGE_VERSION_FULL);
  fprintf (fp, "remote version  .  %s\n",
           v2v_version ? v2v_version : "unknown");
  fprintf (fp, "conversion server  %s\n",
           config->server ? config->server : "none");
  fprintf (fp, "port . . . . . .   %d\n", config->port);
  fprintf (fp, "username . . . .   %s\n",
           config->username ? config->username : "none");
  fprintf (fp, "password . . . .   %s\n",
           config->password && strlen (config->password) > 0 ? "***" : "none");
  fprintf (fp, "identity URL . .   %s\n",
           config->identity_url ? config->identity_url : "none");
  fprintf (fp, "sudo . . . . . .   %s\n",
           config->sudo ? "true" : "false");
  fprintf (fp, "guest name . . .   %s\n",
           config->guestname ? config->guestname : "none");
  fprintf (fp, "vcpus  . . . . .   %d\n", config->vcpus);
  fprintf (fp, "memory . . . . .   %" PRIu64 "\n", config->memory);
  fprintf (fp, "flags  . . . . .  %s%s%s\n",
           config->flags & FLAG_ACPI ? " acpi" : "",
           config->flags & FLAG_APIC ? " apic" : "",
           config->flags & FLAG_PAE  ? " pae"  : "");
  fprintf (fp, "disks  . . . . .  ");
  if (config->disks != NULL) {
    for (i = 0; config->disks[i] != NULL; ++i)
      fprintf (fp, " %s", config->disks[i]);
  }
  fprintf (fp, "\n");
  fprintf (fp, "removable  . . .  ");
  if (config->removable != NULL) {
    for (i = 0; config->removable[i] != NULL; ++i)
      fprintf (fp, " %s", config->removable[i]);
  }
  fprintf (fp, "\n");
  fprintf (fp, "interfaces . . .  ");
  if (config->interfaces != NULL) {
    for (i = 0; config->interfaces[i] != NULL; ++i)
      fprintf (fp, " %s", config->interfaces[i]);
  }
  fprintf (fp, "\n");
  fprintf (fp, "network map  . .  ");
  if (config->network_map != NULL) {
    for (i = 0; config->network_map[i] != NULL; ++i)
      fprintf (fp, " %s", config->network_map[i]);
  }
  fprintf (fp, "\n");
  fprintf (fp, "output . . . . .   %s\n",
           config->output ? config->output : "none");
  fprintf (fp, "output alloc . .   ");
  switch (config->output_allocation) {
  case OUTPUT_ALLOCATION_NONE:         fprintf (fp, "none"); break;
  case OUTPUT_ALLOCATION_SPARSE:       fprintf (fp, "sparse"); break;
  case OUTPUT_ALLOCATION_PREALLOCATED: fprintf (fp, "preallocated"); break;
  default: fprintf (fp, "unknown? (%d)", config->output_allocation);
  }
  fprintf (fp, "\n");
  fprintf (fp, "output conn  . .   %s\n",
           config->output_connection ? config->output_connection : "none");
  fprintf (fp, "output format  .   %s\n",
           config->output_format ? config->output_format : "none");
  fprintf (fp, "output storage .   %s\n",
           config->output_storage ? config->output_storage : "none");
}
