/* libguestfs - the guestfsd daemon
 * Copyright (C) 2021 Red Hat Inc.
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
#include <stdbool.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_LIBRPM
#include <rpm/rpmlib.h>
#include <rpm/header.h>
#include <rpm/rpmts.h>
#include <rpm/rpmdb.h>
#endif

#include "daemon.h"
#include "actions.h"

/* Very lightweight OCaml bindings for librpm. */

#pragma GCC diagnostic ignored "-Wimplicit-function-declaration"
#pragma GCC diagnostic ignored "-Wmissing-prototypes"

#ifndef HAVE_LIBRPM

value __attribute__((noreturn))
guestfs_int_daemon_rpm_init (value unitv)
{
  CAMLparam1 (unitv);
  caml_failwith ("no support for RPM guests because "
                 "librpm was missing at compile time");
}

value __attribute__((noreturn))
guestfs_int_daemon_rpm_start_iterator (value unitv)
{
  guestfs_int_daemon_rpm_init (unitv);
}

value __attribute__((noreturn))
guestfs_int_daemon_rpm_next_application (value unitv)
{
  guestfs_int_daemon_rpm_init (unitv);
}

value __attribute__((noreturn))
guestfs_int_daemon_rpm_end_iterator (value unitv)
{
  guestfs_int_daemon_rpm_init (unitv);
}

#else /* HAVE_LIBRPM */

value
guestfs_int_daemon_rpm_init (value unitv)
{
  CAMLparam1 (unitv);

  /* Nothing in actual RPM C code bothers to check if this call
   * succeeds, so using that as an example, just print a debug message
   * if it failed, but continue.  (The librpm Python bindings do check)
   */
  if (rpmReadConfigFiles (NULL, NULL) == -1)
    fprintf (stderr, "rpmReadConfigFiles: failed, errno=%d\n", errno);

  CAMLreturn (Val_unit);
}

static rpmts ts;
static rpmdbMatchIterator iter;

value
guestfs_int_daemon_rpm_start_iterator (value unitv)
{
  CAMLparam1 (unitv);

  ts = rpmtsCreate ();
  if (ts == NULL)
    caml_failwith ("rpmtsCreate");

#ifdef RPMVSF_MASK_NOSIGNATURES
  /* Disable signature checking (RHBZ#2064182). */
  rpmtsSetVSFlags (ts, rpmtsVSFlags (ts) | RPMVSF_MASK_NOSIGNATURES);
#endif

  iter = rpmtsInitIterator (ts, RPMDBI_PACKAGES, NULL, 0);
  /* This could return NULL in theory if there are no packages, but
   * that could not happen in a real guest.  However it also returns
   * NULL when unable to open the database (RHBZ#2089623) which is
   * something we do need to detect.
   */
  if (iter == NULL)
    caml_failwith ("rpmtsInitIterator");

  CAMLreturn (Val_unit);
}

value
guestfs_int_daemon_rpm_next_application (value unitv)
{
  CAMLparam1 (unitv);
  CAMLlocal2 (rv, sv);
  Header h;
  guestfs_int_application2 app = { 0 };

  h = rpmdbNextIterator (iter);
  if (h == NULL) caml_raise_not_found ();

  h = headerLink (h);
  app.app2_name = headerFormat (h, "%{NAME}", NULL);
  app.app2_version = headerFormat (h, "%{VERSION}", NULL);
  app.app2_release = headerFormat (h, "%{RELEASE}", NULL);
  app.app2_arch = headerFormat (h, "%{ARCH}", NULL);
  app.app2_url = headerFormat (h, "%{URL}", NULL);
  app.app2_summary = headerFormat (h, "%{SUMMARY}", NULL);
  app.app2_description = headerFormat (h, "%{DESCRIPTION}", NULL);

  /* epoch is special as the only int field. */
  app.app2_epoch = headerGetNumber (h, RPMTAG_EPOCH);

  headerFree (h);

  /* Convert this to an OCaml struct.  Any NULL fields must be turned
   * into empty string.
   */
  rv = caml_alloc (17, 0);
#define TO_CAML_STRING(i, name)                     \
  sv = caml_copy_string (app.name ? app.name : ""); \
  Store_field (rv, i, sv);                          \
  free (app.name)

  TO_CAML_STRING (0, app2_name);
  TO_CAML_STRING (1, app2_display_name);
  sv = caml_copy_int32 (app.app2_epoch);
  Store_field (rv, 2, sv);
  TO_CAML_STRING (3, app2_version);
  TO_CAML_STRING (4, app2_release);
  TO_CAML_STRING (5, app2_arch);
  TO_CAML_STRING (6, app2_install_path);
  TO_CAML_STRING (7, app2_trans_path);
  TO_CAML_STRING (8, app2_publisher);
  TO_CAML_STRING (9, app2_url);
  TO_CAML_STRING (10, app2_source_package);
  TO_CAML_STRING (11, app2_summary);
  TO_CAML_STRING (12, app2_description);
  TO_CAML_STRING (13, app2_spare1);
  TO_CAML_STRING (14, app2_spare2);
  TO_CAML_STRING (15, app2_spare3);
  TO_CAML_STRING (16, app2_spare4);
#undef TO_CAML_STRING

  CAMLreturn (rv);
}

value
guestfs_int_daemon_rpm_end_iterator (value unitv)
{
  CAMLparam1 (unitv);
  rpmdbFreeIterator (iter);
  rpmtsFree (ts);
  CAMLreturn (Val_unit);
}

#endif /* HAVE_LIBRPM */
