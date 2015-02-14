/* virt-df
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <libintl.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "guestfs.h"
#include "guestfs-internal-frontend.h"
#include "domains.h"

#if defined(HAVE_LIBVIRT)

virConnectPtr conn = NULL;
struct domain *domains = NULL;
size_t nr_domains = 0;

static int
compare_domain_names (const void *p1, const void *p2)
{
  const struct domain *d1 = p1;
  const struct domain *d2 = p2;

  return strcmp (d1->name, d2->name);
}

void
free_domains (void)
{
  size_t i;

  for (i = 0; i < nr_domains; ++i) {
    free (domains[i].name);
    free (domains[i].uuid);
    virDomainFree (domains[i].dom);
  }

  free (domains);

  if (conn)
    virConnectClose (conn);
}

static void add_domains_by_id (virConnectPtr conn, int *ids, size_t n);
static void add_domains_by_name (virConnectPtr conn, char **names, size_t n);
static void add_domain (virDomainPtr dom);

void
get_all_libvirt_domains (const char *libvirt_uri)
{
  virErrorPtr err;
  int n;
  size_t i;

  /* Get the list of all domains. */
  conn = virConnectOpenReadOnly (libvirt_uri);
  if (!conn) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not connect to libvirt (code %d, domain %d): %s\n"),
             guestfs_int_program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  n = virConnectNumOfDomains (conn);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not get number of running domains (code %d, domain %d): %s\n"),
             guestfs_int_program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  int ids[n];
  n = virConnectListDomains (conn, ids, n);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not list running domains (code %d, domain %d): %s\n"),
             guestfs_int_program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  add_domains_by_id (conn, ids, n);

  n = virConnectNumOfDefinedDomains (conn);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not get number of inactive domains (code %d, domain %d): %s\n"),
             guestfs_int_program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  char *names[n];
  n = virConnectListDefinedDomains (conn, names, n);
  if (n == -1) {
    err = virGetLastError ();
    fprintf (stderr,
             _("%s: could not list inactive domains (code %d, domain %d): %s\n"),
             guestfs_int_program_name, err->code, err->domain, err->message);
    exit (EXIT_FAILURE);
  }

  add_domains_by_name (conn, names, n);

  /* You must free these even though the libvirt documentation doesn't
   * mention it.
   */
  for (i = 0; i < (size_t) n; ++i)
    free (names[i]);

  /* No domains? */
  if (nr_domains == 0)
    return;

  /* Sort the domains alphabetically by name for display. */
  qsort (domains, nr_domains, sizeof (struct domain), compare_domain_names);
}

static void
add_domains_by_id (virConnectPtr conn, int *ids, size_t n)
{
  size_t i;
  virDomainPtr dom;

  for (i = 0; i < n; ++i) {
    if (ids[i] != 0) {          /* RHBZ#538041 */
      dom = virDomainLookupByID (conn, ids[i]);
      if (dom)   /* transient errors are possible here, ignore them */
        add_domain (dom);
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
    if (dom)     /* transient errors are possible here, ignore them */
      add_domain (dom);
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

  domain->dom = dom;

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
}

#endif /* HAVE_LIBVIRT */
