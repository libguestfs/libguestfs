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

/**
 * This file is used by C<virt-df> and some of the other tools
 * when they are implicitly asked to operate over all libvirt
 * domains (VMs), for example when C<virt-df> is called without
 * specifying any particular disk image.
 *
 * It hides the complexity of querying the list of domains from
 * libvirt.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <error.h>
#include <libintl.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "guestfs.h"
#include "guestfs-utils.h"
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

/**
 * Frees up everything allocated by C<get_all_libvirt_domains>.
 */
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

/**
 * Read all libguest guests into the global variables C<domains> and
 * C<nr_domains>.  The guests are ordered by name.  This exits on any
 * error.
 */
void
get_all_libvirt_domains (const char *libvirt_uri)
{
  virErrorPtr err;
  int n;
  size_t i;
  CLEANUP_FREE int *ids = NULL;
  CLEANUP_FREE char **names = NULL;

  /* Get the list of all domains. */
  conn = virConnectOpenAuth (libvirt_uri, virConnectAuthPtrDefault,
                             VIR_CONNECT_RO);
  if (!conn) {
    err = virGetLastError ();
    error (EXIT_FAILURE, 0,
           _("could not connect to libvirt (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
  }

  n = virConnectNumOfDomains (conn);
  if (n == -1) {
    err = virGetLastError ();
    error (EXIT_FAILURE, 0,
           _("could not get number of running domains (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
  }

  ids = malloc (sizeof (int) * n);
  if (ids == NULL)
    error (EXIT_FAILURE, errno, "malloc");
  n = virConnectListDomains (conn, ids, n);
  if (n == -1) {
    err = virGetLastError ();
    error (EXIT_FAILURE, 0,
           _("could not list running domains (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
  }

  add_domains_by_id (conn, ids, n);

  n = virConnectNumOfDefinedDomains (conn);
  if (n == -1) {
    err = virGetLastError ();
    error (EXIT_FAILURE, 0,
           _("could not get number of inactive domains (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
  }

  names = malloc (sizeof (char *) * n);
  if (names == NULL)
    error (EXIT_FAILURE, errno, "malloc");
  n = virConnectListDefinedDomains (conn, names, n);
  if (n == -1) {
    err = virGetLastError ();
    error (EXIT_FAILURE, 0,
           _("could not list inactive domains (code %d, domain %d): %s"),
           err->code, err->domain, err->message);
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
  if (domains == NULL)
    error (EXIT_FAILURE, errno, "realloc");

  domain = &domains[nr_domains];
  nr_domains++;

  domain->dom = dom;

  domain->name = strdup (virDomainGetName (dom));
  if (domain->name == NULL)
    error (EXIT_FAILURE, errno, "strdup");

  char uuid[VIR_UUID_STRING_BUFLEN];
  if (virDomainGetUUIDString (dom, uuid) == 0) {
    domain->uuid = strdup (uuid);
    if (domain->uuid == NULL)
      error (EXIT_FAILURE, errno, "strdup");
  }
  else
    domain->uuid = NULL;
}

#endif /* HAVE_LIBVIRT */
