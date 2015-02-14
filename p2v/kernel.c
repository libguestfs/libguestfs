/* virt-p2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

/* Kernel-driven configuration, non-interactive. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <assert.h>
#include <locale.h>
#include <libintl.h>

#include "p2v.h"

static void notify_ui_callback (int type, const char *data);

void
kernel_configuration (struct config *config, const char *cmdline)
{
  const char *r;
  size_t len;

  r = strstr (cmdline, "p2v.server=");
  assert (r); /* checked by caller */
  r += 5+6;
  len = strcspn (r, " ");
  free (config->server);
  config->server = strndup (r, len);

  r = strstr (cmdline, "p2v.port=");
  if (r) {
    r += 5+4;
    if (sscanf (r, "%d", &config->port) != 1) {
      fprintf (stderr, "%s: cannot parse p2v.port from kernel command line",
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }
  }

  r = strstr (cmdline, "p2v.username=");
  if (r) {
    r += 5+8;
    len = strcspn (r, " ");
    free (config->username);
    config->username = strndup (r, len);
  }

  r = strstr (cmdline, "p2v.password=");
  if (r) {
    r += 5+8;
    len = strcspn (r, " ");
    free (config->password);
    config->password = strndup (r, len);
  }

  r = strstr (cmdline, "p2v.sudo");
  if (r)
    config->sudo = 1;

  /* We should now be able to connect and interrogate virt-v2v
   * on the conversion server.
   */
  if (test_connection (config) == -1) {
    const char *err = get_ssh_error ();

    fprintf (stderr, "%s: error opening control connection to %s:%d: %s\n",
             guestfs_int_program_name, config->server, config->port, err);
    exit (EXIT_FAILURE);
  }

  r = strstr (cmdline, "p2v.name=");
  if (r) {
    r += 5+4;
    len = strcspn (r, " ");
    free (config->guestname);
    config->guestname = strndup (r, len);
  }

  r = strstr (cmdline, "p2v.vcpus=");
  if (r) {
    r += 5+5;
    if (sscanf (r, "%d", &config->vcpus) != 1) {
      fprintf (stderr, "%s: cannot parse p2v.vcpus from kernel command line\n",
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }
  }

  r = strstr (cmdline, "p2v.memory=");
  if (r) {
    char mem_code[2];

    r += 5+6;
    if (sscanf (r, "%" SCNu64 "%c", &config->memory, mem_code) != 1) {
      fprintf (stderr, "%s: cannot parse p2v.memory from kernel command line\n",
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }
    config->memory *= 1024;
    if (mem_code[0] == 'M' || mem_code[0] == 'G')
      config->memory *= 1024;
    if (mem_code[0] == 'G')
      config->memory *= 1024;
    if (mem_code[0] != 'M' && mem_code[0] != 'G') {
      fprintf (stderr, "%s: p2v.memory on kernel command line must be followed by 'G' or 'M'\n",
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }
  }

  r = strstr (cmdline, "p2v.disks=");
  if (r) {
    CLEANUP_FREE char *t;

    r += 5+5;
    len = strcspn (r, " ");
    t = strndup (r, len);
    guestfs_int_free_string_list (config->disks);
    config->disks = guestfs_int_split_string (',', t);
  }

  r = strstr (cmdline, "p2v.removable=");
  if (r) {
    CLEANUP_FREE char *t;

    r += 5+9;
    len = strcspn (r, " ");
    t = strndup (r, len);
    guestfs_int_free_string_list (config->removable);
    config->removable = guestfs_int_split_string (',', t);
  }

  r = strstr (cmdline, "p2v.interfaces=");
  if (r) {
    CLEANUP_FREE char *t;

    r += 5+10;
    len = strcspn (r, " ");
    t = strndup (r, len);
    guestfs_int_free_string_list (config->interfaces);
    config->interfaces = guestfs_int_split_string (',', t);
  }

  r = strstr (cmdline, "p2v.network=");
  if (r) {
    CLEANUP_FREE char *t;

    r += 5+7;
    len = strcspn (r, " ");
    t = strndup (r, len);
    guestfs_int_free_string_list (config->network_map);
    config->network_map = guestfs_int_split_string (',', t);
  }

  r = strstr (cmdline, "p2v.o=");
  if (r) {
    r += 5+1;
    len = strcspn (r, " ");
    free (config->output);
    config->output = strndup (r, len);
  }

  r = strstr (cmdline, "p2v.oa=sparse");
  if (r)
    config->output_allocation = OUTPUT_ALLOCATION_SPARSE;

  r = strstr (cmdline, "p2v.oa=preallocated");
  if (r)
    config->output_allocation = OUTPUT_ALLOCATION_PREALLOCATED;

  r = strstr (cmdline, "p2v.oc=");
  if (r) {
    r += 5+2;
    len = strcspn (r, " ");
    free (config->output_connection);
    config->output_connection = strndup (r, len);
  }

  r = strstr (cmdline, "p2v.of=");
  if (r) {
    r += 5+2;
    len = strcspn (r, " ");
    free (config->output_format);
    config->output_format = strndup (r, len);
  }

  r = strstr (cmdline, "p2v.os=");
  if (r) {
    r += 5+2;
    len = strcspn (r, " ");
    free (config->output_storage);
    config->output_storage = strndup (r, len);
  }

  /* Perform the conversion in text mode. */
  if (start_conversion (config, notify_ui_callback) == -1) {
    const char *err = get_conversion_error ();

    fprintf (stderr, "%s: error during conversion: %s\n",
             guestfs_int_program_name, err);
    exit (EXIT_FAILURE);
  }
}

static void
notify_ui_callback (int type, const char *data)
{
  switch (type) {
  case NOTIFY_LOG_DIR:
    printf ("%s: remote log directory location: %s\n", guestfs_int_program_name, data);
    break;

  case NOTIFY_REMOTE_MESSAGE:
    printf ("%s", data);
    break;

  case NOTIFY_STATUS:
    printf ("%s: %s\n", guestfs_int_program_name, data);
    break;

  default:
    printf ("%s: unknown message during conversion: type=%d data=%s\n",
            guestfs_int_program_name, type, data);
  }
}
