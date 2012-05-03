/* virt-alignment-scan
 * Copyright (C) 2012 Red Hat Inc.
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
#include <libintl.h>
#include <assert.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "progname.h"

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)
#define GUESTFS_PRIVATE_FOR_EACH_DISK 1
#endif

#include "guestfs.h"
#include "options.h"
#include "scan.h"

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)

/* The list of domains and disks that we build up in
 * get_domains_from_libvirt.
 */
struct disk {
  struct disk *next;
  char *filename;
  char *format; /* could be NULL */
};

struct domain {
  char *name;
  char *uuid;
  struct disk *disks;
  size_t nr_disks;
};

struct domain *domains = NULL;
size_t nr_domains;

static int
compare_domain_names (const void *p1, const void *p2)
{
  const struct domain *d1 = p1;
  const struct domain *d2 = p2;

  return strcmp (d1->name, d2->name);
}

static void
free_domain (struct domain *domain)
{
  struct disk *disk, *next;

  for (disk = domain->disks; disk; disk = next) {
    next = disk->next;
    free (disk->filename);
    free (disk->format);
    free (disk);
  }

  free (domain->name);
  free (domain->uuid);
}

static void add_domains_by_id (virConnectPtr conn, int *ids, size_t n);
static void add_domains_by_name (virConnectPtr conn, char **names, size_t n);
static void add_domain (virDomainPtr dom);
static int add_disk (guestfs_h *g, const char *filename, const char *format, int readonly, void *domain_vp);
static size_t add_disks_to_handle_reverse (struct disk *disk, size_t *errors_r);
static void reset_guestfs_handle (void);

void
get_domains_from_libvirt (int uuid, size_t *worst_alignment_ptr)
{
  virErrorPtr err;
  virConnectPtr conn;
  int n;
  size_t i, count, errors;
  const char *prefix;

  nr_domains = 0;
  domains = NULL;

  /* Get the list of all domains. */
  conn = virConnectOpenReadOnly (libvirt_uri);
  if (!conn) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not connect to libvirt (code %d, domain %d): %s\n"),
             program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  n = virConnectNumOfDomains (conn);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not get number of running domains (code %d, domain %d): %s\n"),
             program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  int ids[n];
  n = virConnectListDomains (conn, ids, n);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not list running domains (code %d, domain %d): %s\n"),
             program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  add_domains_by_id (conn, ids, n);

  n = virConnectNumOfDefinedDomains (conn);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not get number of inactive domains (code %d, domain %d): %s\n"),
             program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  char *names[n];
  n = virConnectListDefinedDomains (conn, names, n);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not list inactive domains (code %d, domain %d): %s\n"),
             program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  add_domains_by_name (conn, names, n);

  /* You must free these even though the libvirt documentation doesn't
   * mention it.
   */
  for (i = 0; i < (size_t) n; ++i)
    free (names[i]);

  virConnectClose (conn);

  /* No domains? */
  if (nr_domains == 0)
    return;

  /* Sort the domains alphabetically by name for display. */
  qsort (domains, nr_domains, sizeof (struct domain), compare_domain_names);

  errors = 0;
  for (i = 0; i < nr_domains; ++i) {
    if (domains[i].disks == NULL)
      continue;

    count = add_disks_to_handle_reverse (domains[i].disks, &errors);
    if (count == 0)
      continue;

    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);

    prefix = !uuid ? domains[i].name : domains[i].uuid;

    /* Perform the scan. */
    scan (worst_alignment_ptr, prefix);

    if (i < nr_domains - 1)
      reset_guestfs_handle ();
  }

  /* Free up domains structure. */
  for (i = 0; i < nr_domains; ++i)
    free_domain (&domains[i]);
  free (domains);

  if (errors > 0) {
    fprintf (stderr, _("%s: failed to analyze a disk, see error(s) above\n"),
             program_name);
    exit (EXIT_FAILURE);
  }
}

static void
add_domains_by_id (virConnectPtr conn, int *ids, size_t n)
{
  size_t i;
  virDomainPtr dom;

  for (i = 0; i < n; ++i) {
    if (ids[i] != 0) {          /* RHBZ#538041 */
      dom = virDomainLookupByID (conn, ids[i]);
      if (dom) { /* transient errors are possible here, ignore them */
        add_domain (dom);
        virDomainFree (dom);
      }
    }
  }
}

static void
add_domains_by_name (virConnectPtr conn, char **names, size_t n)
{
  size_t i;
  virDomainPtr dom;

  for (i = 0; i < n; ++i) {
    dom = virDomainLookupByName (conn, names[i]);
    if (dom) { /* transient errors are possible here, ignore them */
      add_domain (dom);
      virDomainFree (dom);
    }
  }
}

static void
add_domain (virDomainPtr dom)
{
  struct domain *domain;

  domains = realloc (domains, (nr_domains + 1) * sizeof (struct domain));
  if (domains == NULL) {
    perror ("realloc");
    exit (EXIT_FAILURE);
  }

  domain = &domains[nr_domains];
  nr_domains++;

  domain->name = strdup (virDomainGetName (dom));
  if (domain->name == NULL) {
    perror ("strdup");
    exit (EXIT_FAILURE);
  }

  char uuid[VIR_UUID_STRING_BUFLEN];
  if (virDomainGetUUIDString (dom, uuid) == 0) {
    domain->uuid = strdup (uuid);
    if (domain->uuid == NULL) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
  }
  else
    domain->uuid = NULL;

  domain->disks = NULL;
  int n = guestfs___for_each_disk (g, dom, add_disk, domain);
  if (n == -1)
    exit (EXIT_FAILURE);
  domain->nr_disks = n;
}

static int
add_disk (guestfs_h *g,
          const char *filename, const char *format, int readonly,
          void *domain_vp)
{
  struct domain *domain = domain_vp;
  struct disk *disk;

  disk = malloc (sizeof *disk);
  if (disk == NULL) {
    perror ("malloc");
    return -1;
  }

  disk->next = domain->disks;
  domain->disks = disk;

  disk->filename = strdup (filename);
  if (disk->filename == NULL) {
    perror ("malloc");
    return -1;
  }
  if (format) {
    disk->format = strdup (format);
    if (disk->format == NULL) {
      perror ("malloc");
      return -1;
    }
  }
  else
    disk->format = NULL;

  return 0;
}

static size_t
add_disks_to_handle_reverse (struct disk *disk, size_t *errors_r)
{
  size_t nr_disks_added;

  if (disk == NULL)
    return 0;

  nr_disks_added = add_disks_to_handle_reverse (disk->next, errors_r);

  struct guestfs_add_drive_opts_argv optargs = { .bitmask = 0 };

  optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK;
  optargs.readonly = 1;

  if (disk->format) {
    optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
    optargs.format = disk->format;
  }

  if (guestfs_add_drive_opts_argv (g, disk->filename, &optargs) == -1) {
    (*errors_r)++;
    return nr_disks_added;
  }

  return nr_disks_added+1;
}

/* Close and reopen the libguestfs handle. */
static void
reset_guestfs_handle (void)
{
  /* Copy the settings from the old handle. */
  int verbose = guestfs_get_verbose (g);
  int trace = guestfs_get_trace (g);

  guestfs_close (g);

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  guestfs_set_verbose (g, verbose);
  guestfs_set_trace (g, trace);
}

#endif
