/* virt-p2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * Find CPU vendor, topology and some CPU flags.
 *
 * lscpu (from util-linux) provides CPU vendor, topology and flags.
 *
 * ACPI can be read by seeing if F</sys/firmware/acpi> exists.
 *
 * CPU model is essentially impossible to get without using libvirt,
 * but we cannot use libvirt for the reasons outlined in this message:
 * https://www.redhat.com/archives/libvirt-users/2017-March/msg00071.html
 *
 * Note that #vCPUs and amount of RAM is handled by F<main.c>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <error.h>
#include <libintl.h>

#include "c-ctype.h"
#include "getprogname.h"
#include "ignore-value.h"

#include "p2v.h"

static void
free_cpu_config (struct cpu_config *cpu)
{
  if (cpu->vendor)
    free (cpu->vendor);
  if (cpu->model)
    free (cpu->model);
  memset (cpu, 0, sizeof *cpu);
}

/**
 * Get the output of lscpu as a list of (key, value) pairs (as a
 * flattened list of strings).
 */
static char **
get_lscpu (void)
{
  const char *cmd;
  CLEANUP_PCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *line = NULL;
  ssize_t len;
  size_t buflen = 0;
  char **ret = NULL;
  size_t ret_size = 0;

  cmd = "lscpu";

  fp = popen (cmd, "re");
  if (fp == NULL) {
    perror (cmd);
    return NULL;
  }

  ret = malloc (sizeof (char *));
  if (ret == NULL) error (EXIT_FAILURE, errno, "malloc");
  ret[0] = NULL;

  while (errno = 0, (len = getline (&line, &buflen, fp)) != -1) {
    char *p;
    char *key, *value;

    if (len > 0 && line[len-1] == '\n')
      line[len-1] = '\0';

    /* Split the line at the first ':' character. */
    p = strchr (line, ':');
    if (p == NULL)
      continue;

    *p = '\0';
    key = strdup (line);
    /* Skip leading whitespace in the value. */
    for (++p; *p && c_isspace (*p); ++p)
      ;
    value = strdup (p);

    /* Add key and value to the list, and trailing NULL pointer. */
    ret_size += 2;
    ret = realloc (ret, (ret_size + 1) * sizeof (char *));
    if (ret == NULL) error (EXIT_FAILURE, errno, "realloc");
    ret[ret_size-2] = key;
    ret[ret_size-1] = value;
    ret[ret_size] = NULL;
  }

  if (errno) {
    perror (cmd);
    guestfs_int_free_string_list (ret);
    return NULL;
  }

  return ret;
}

/**
 * Read a single field from lscpu output.
 *
 * If the field does not exist, returns C<NULL>.
 */
static const char *
get_field (char **lscpu, const char *key)
{
  size_t i;

  for (i = 0; lscpu[i] != NULL; i += 2) {
    if (STREQ (lscpu[i], key))
      return lscpu[i+1];
  }

  return NULL;
}

/**
 * Read the CPU vendor from lscpu output.
 */
static void
get_vendor (char **lscpu, struct cpu_config *cpu)
{
  const char *vendor = get_field (lscpu, "Vendor ID");

  if (vendor) {
    /* Note this mapping comes from /usr/share/libvirt/cpu_map.xml */
    if (STREQ (vendor, "GenuineIntel"))
      cpu->vendor = strdup ("Intel");
    else if (STREQ (vendor, "AuthenticAMD"))
      cpu->vendor = strdup ("AMD");
    /* Currently aarch64 lscpu has no Vendor ID XXX. */
  }
}

/**
 * Read the CPU topology from lscpu output.
 */
static void
get_topology (char **lscpu, struct cpu_config *cpu)
{
  const char *v;

  v = get_field (lscpu, "Socket(s)");
  if (v)
    ignore_value (sscanf (v, "%u", &cpu->sockets));
  v = get_field (lscpu, "Core(s) per socket");
  if (v)
    ignore_value (sscanf (v, "%u", &cpu->cores));
  v = get_field (lscpu, "Thread(s) per core");
  if (v)
    ignore_value (sscanf (v, "%u", &cpu->threads));
}

/**
 * Read some important flags from lscpu output.
 */
static void
get_flags (char **lscpu, struct cpu_config *cpu)
{
  const char *flags;

  flags = get_field (lscpu, "Flags");
  if (flags) {
    cpu->apic = strstr (flags, " apic ") != NULL;
    cpu->pae = strstr (flags, " pae ") != NULL;

    /* aarch64 /proc/cpuinfo has a "Features" field, but lscpu does
     * not expose it.  However aarch64 Features does not contain any
     * of the interesting flags above.
     */
  }
}

/**
 * Find out if the system uses ACPI.
 */
static void
get_acpi (struct cpu_config *cpu)
{
  cpu->acpi = access ("/sys/firmware/acpi", F_OK) == 0;
}

void
get_cpu_config (struct cpu_config *cpu)
{
  CLEANUP_FREE_STRING_LIST char **lscpu = NULL;

  free_cpu_config (cpu);

  lscpu = get_lscpu ();
  if (lscpu != NULL) {
    get_vendor (lscpu, cpu);
    get_topology (lscpu, cpu);
    get_flags (lscpu, cpu);
  }

  get_acpi (cpu);
}
