/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#ifdef HAVE_LIBXML2
#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)

static struct {
  int credtype;
  const char *credname;
} libvirt_credential_types[NR_CREDENTIAL_TYPES] = {
  { VIR_CRED_USERNAME,     "username" },
  { VIR_CRED_AUTHNAME,     "authname" },
  { VIR_CRED_LANGUAGE,     "language" },
  { VIR_CRED_CNONCE,       "cnonce" },
  { VIR_CRED_PASSPHRASE,   "passphrase" },
  { VIR_CRED_ECHOPROMPT,   "echoprompt" },
  { VIR_CRED_NOECHOPROMPT, "noechoprompt" },
  { VIR_CRED_REALM,        "realm" },
  { VIR_CRED_EXTERNAL,     "external" },
};

static int
get_credtype_from_string (const char *name)
{
  size_t i;

  for (i = 0; i < NR_CREDENTIAL_TYPES; ++i)
    if (STREQ (name, libvirt_credential_types[i].credname))
      return libvirt_credential_types[i].credtype;

  return -1;
}

static const char *
get_string_of_credtype (int credtype)
{
  size_t i;

  for (i = 0; i < NR_CREDENTIAL_TYPES; ++i)
    if (credtype == libvirt_credential_types[i].credtype)
      return libvirt_credential_types[i].credname;

  return NULL;
}

/* Note to callers: Should it be possible to say that you don't
 * support any libvirt credential types at all?  Not clear if that's
 * an error or not, so don't depend on the current behaviour.
 */
int
guestfs__set_libvirt_supported_credentials (guestfs_h *g, char *const *creds)
{
  size_t i;
  int credtype;

  /* Try to make this call atomic so it either completely succeeds
   * or if it fails it leaves the current state intact.
   */
  unsigned int ncredtypes = 0;
  int credtypes[NR_CREDENTIAL_TYPES];

  for (i = 0; creds[i] != NULL; ++i) {
    credtype = get_credtype_from_string (creds[i]);
    if (credtype == -1) {
      error (g, _("unknown credential type '%s'"), creds[i]);
      return -1;
    }

    if (ncredtypes >= NR_CREDENTIAL_TYPES) {
      error (g, _("list of supported credentials is too long"));
      return -1;
    }

    credtypes[ncredtypes++] = credtype;
  }

  g->nr_supported_credentials = ncredtypes;
  memcpy (g->supported_credentials, credtypes, sizeof g->supported_credentials);

  return 0;
}

/* This function is called back from libvirt.  In turn it generates a
 * libguestfs event to collect the desired credentials.
 */
static int
libvirt_auth_callback (virConnectCredentialPtr cred,
                       unsigned int ncred,
                       void *gv)
{
  guestfs_h *g = gv;
  size_t i;

  if (cred == NULL || ncred == 0)
    return 0;

  /* libvirt probably does this already, but no harm in checking. */
  for (i = 0; i < ncred; ++i) {
    cred[i].result = NULL;
    cred[i].resultlen = 0;
  }

  g->requested_credentials = cred;
  g->nr_requested_credentials = ncred;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_LIBVIRT_AUTH,
                                    g->saved_libvirt_uri,
                                    strlen (g->saved_libvirt_uri));

  /* Clarified with Dan that it is not an error for some fields to be
   * left as NULL.
   * https://www.redhat.com/archives/libvir-list/2012-October/msg00707.html
   */
  return 0;
}

static int
exists_libvirt_auth_event (guestfs_h *g)
{
  size_t i;

  for (i = 0; i < g->nr_events; ++i)
    if ((g->events[i].event_bitmask & GUESTFS_EVENT_LIBVIRT_AUTH) != 0)
      return 1;

  return 0;
}

/* Open a libvirt connection (called from other parts of the library). */
virConnectPtr
guestfs___open_libvirt_connection (guestfs_h *g, const char *uri,
                                   unsigned int flags)
{
  virConnectAuth authdata;
  virConnectAuthPtr authdataptr;
  virConnectPtr conn;

  /* Did the caller register a GUESTFS_EVENT_LIBVIRT_AUTH event and
   * call guestfs_set_libvirt_supported_credentials?
   */
  if (g->nr_supported_credentials > 0 && exists_libvirt_auth_event (g)) {
    memset (&authdata, 0, sizeof authdata);
    authdata.credtype = g->supported_credentials;
    authdata.ncredtype = g->nr_supported_credentials;
    authdata.cb = libvirt_auth_callback;
    authdata.cbdata = g;
    authdataptr = &authdata;
    g->saved_libvirt_uri = uri;
  }
  else
    authdataptr = virConnectAuthPtrDefault;

  conn = virConnectOpenAuth (uri, authdataptr, flags);

  /* Restore handle fields to "outside event handler" state. */
  g->saved_libvirt_uri = NULL;
  g->nr_requested_credentials = 0;
  g->requested_credentials = NULL;

  return conn;
}

/* The calls below are meant to be called recursively from
 * the GUESTFS_EVENT_LIBVIRT_AUTH event.
 */
#define CHECK_IN_EVENT_HANDLER(r)                                       \
  if (g->nr_requested_credentials == 0) {                               \
    error (g, _("%s should only be called from within the GUESTFS_EVENT_LIBVIRT_AUTH event handler"), \
           __func__);                                                   \
    return r;                                                           \
  }

char **
guestfs__get_libvirt_requested_credentials (guestfs_h *g)
{
  char **ret;
  size_t i;

  CHECK_IN_EVENT_HANDLER (NULL);

  /* Convert the requested_credentials types to a list of strings. */
  ret = safe_malloc (g, sizeof (char *) * (g->nr_requested_credentials+1));
  for (i = 0; i < g->nr_requested_credentials; ++i) {
    ret[i] = safe_strdup (g,
      get_string_of_credtype (g->requested_credentials[i].type));
  }
  ret[i] = NULL;

  return ret;                   /* caller frees */
}

char *
guestfs__get_libvirt_requested_credential_prompt (guestfs_h *g, int index)
{
  size_t i;

  CHECK_IN_EVENT_HANDLER (NULL);

  if (index >= 0 && (unsigned int) index < g->nr_requested_credentials)
    i = (size_t) index;
  else {
    error (g, _("credential index out of range"));
    return NULL;
  }

  if (g->requested_credentials[i].prompt)
    return safe_strdup (g, g->requested_credentials[i].prompt);
  else
    return safe_strdup (g, "");
}

char *
guestfs__get_libvirt_requested_credential_challenge (guestfs_h *g, int index)
{
  size_t i;

  CHECK_IN_EVENT_HANDLER (NULL);

  if (index >= 0 && (unsigned int) index < g->nr_requested_credentials)
    i = (size_t) index;
  else {
    error (g, _("credential index out of range"));
    return NULL;
  }

  if (g->requested_credentials[i].challenge)
    return safe_strdup (g, g->requested_credentials[i].challenge);
  else
    return safe_strdup (g, "");
}

char *
guestfs__get_libvirt_requested_credential_defresult (guestfs_h *g, int index)
{
  size_t i;

  CHECK_IN_EVENT_HANDLER (NULL);

  if (index >= 0 && (unsigned int) index < g->nr_requested_credentials)
    i = (size_t) index;
  else {
    error (g, _("credential index out of range"));
    return NULL;
  }

  if (g->requested_credentials[i].defresult)
    return safe_strdup (g, g->requested_credentials[i].defresult);
  else
    return safe_strdup (g, "");
}

int
guestfs__set_libvirt_requested_credential (guestfs_h *g, int index,
                                           const char *cred, size_t cred_size)
{
  size_t i;

  CHECK_IN_EVENT_HANDLER (-1);

  if (index >= 0 && (unsigned int) index < g->nr_requested_credentials)
    i = (size_t) index;
  else {
    error (g, _("credential index out of range"));
    return -1;
  }

  /* All the evidence is that libvirt will free this. */
  g->requested_credentials[i].result = safe_malloc (g, cred_size+1 /* sic */);
  memcpy (g->requested_credentials[i].result, cred, cred_size);
  /* Some libvirt drivers are buggy (eg. libssh2), and they expect
   * that the cred field will be \0 terminated.  To avoid surprises,
   * add a \0 at the end.  See also:
   * https://www.redhat.com/archives/libvir-list/2012-October/msg00711.html
   */
  g->requested_credentials[i].result[cred_size] = 0;
  g->requested_credentials[i].resultlen = cred_size;
  return 0;
}

#else /* no libvirt or libxml2 at compile time */

#define NOT_IMPL(r)                                                     \
  error (g, _("libvirt authentication APIs not available since this version of libguestfs was compiled without libvirt or libxml2")); \
  return r

int
guestfs__set_libvirt_supported_credentials (guestfs_h *g, char *const *creds)
{
  NOT_IMPL(-1);
}

char **
guestfs__get_libvirt_requested_credentials (guestfs_h *g)
{
  NOT_IMPL(NULL);
}

char *
guestfs__get_libvirt_requested_credential_prompt (guestfs_h *g, int index)
{
  NOT_IMPL(NULL);
}

char *
guestfs__get_libvirt_requested_credential_challenge (guestfs_h *g, int index)
{
  NOT_IMPL(NULL);
}

char *
guestfs__get_libvirt_requested_credential_defresult (guestfs_h *g, int index)
{
  NOT_IMPL(NULL);
}

int
guestfs__set_libvirt_requested_credential (guestfs_h *g, int index, const char *cred, size_t cred_size)
{
  NOT_IMPL(-1);
}

#endif /* no libvirt or libxml2 at compile time */
