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

#include "guestfs.h"
#include "guestfs-utils.h"

#define EXPECT_OK 1
#define EXPECT_FAIL -1

struct auth_data {
  const char *username;
  const char *password;
};

static void do_test (const char *prog, const char *libvirt_uri, const struct auth_data *auth_data, int expected);
static void auth_callback (guestfs_h *g, void *opaque, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

int
main (int argc, char *argv[])
{
  unsigned long ver;
  const char *srcdir;
  char *cwd;
  char *test_uri;

  virInitialize ();

  /* Check that the version of libvirt we are linked against
   * supports the new test-driver auth feature.
   */
  virGetVersion (&ver, NULL, NULL);
  if (ver < 1002001)
    error (77, 0, "test skipped because libvirt is too old (%lu)", ver);

  /* $srcdir must have been passed (by automake). */
  srcdir = getenv ("srcdir");
  if (!srcdir)
    error (EXIT_FAILURE, 0,
           "environment variable $srcdir is not defined.\n"
           "Normally it is defined by automake.  If you are running the\n"
           "tests directly, set $srcdir to point to the source tests/events\n"
           "directory.");

  cwd = getcwd (NULL, 0);
  if (cwd == NULL)
    error (EXIT_FAILURE, errno, "getcwd");

  if (asprintf (&test_uri, "test://%s/%s/events/libvirt-auth.xml",
                cwd, srcdir) == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  free (cwd);

  /* Perform the tests. */
  struct auth_data ad1 = { .username = "rich", .password = "123456" };
  do_test (argv[0], test_uri, &ad1, EXPECT_OK);
  struct auth_data ad2 = { .username = "rich", .password = "654321" };
  do_test (argv[0], test_uri, &ad2, EXPECT_FAIL);
  struct auth_data ad3 = { .username = "jane", .password = NULL };
  do_test (argv[0], test_uri, &ad3, EXPECT_OK);
  struct auth_data ad4 = { .username = "nouser", .password = "123456" };
  do_test (argv[0], test_uri, &ad4, EXPECT_FAIL);

  free (test_uri);
  exit (EXIT_SUCCESS);
}

static void
do_test (const char *prog, const char *libvirt_uri,
         const struct auth_data *auth_data,
         int expected)
{
  guestfs_h *g;
  const char *creds[] =
    { "authname", "passphrase", "noechoprompt", NULL };
  int r, eh;

  g = guestfs_create ();
  if (!g)
    error (EXIT_FAILURE, errno, "guestfs_create");

  r = guestfs_set_libvirt_supported_credentials (g, (char **) creds);
  if (r == -1)
    exit (EXIT_FAILURE);

  eh = guestfs_set_event_callback (g, auth_callback,
                                   GUESTFS_EVENT_LIBVIRT_AUTH, 0,
                                   (void *) auth_data);
  if (eh == -1)
    exit (EXIT_FAILURE);

  r = guestfs_add_domain (g, "test",
                          GUESTFS_ADD_DOMAIN_LIBVIRTURI, libvirt_uri,
                          GUESTFS_ADD_DOMAIN_READONLY, 1,
                          -1);
  if (r != expected)
    error (EXIT_FAILURE, 0,
           "test failed: u=%s p=%s: got %d expected %d",
           auth_data->username, auth_data->password ? : "(none)",
           r, expected);

  guestfs_close (g);
}

static void
auth_callback (guestfs_h *g, void *opaque,
               uint64_t event, int event_handle,
               int flags,
               const char *buf, size_t buf_len,
               const uint64_t *array, size_t array_len)
{
  CLEANUP_FREE_STRING_LIST char **creds = NULL;
  const struct auth_data *auth_data = opaque;
  size_t i;
  int r;
  const char *reply;
  size_t len;

  /* Ask libguestfs what credentials libvirt is demanding. */
  creds = guestfs_get_libvirt_requested_credentials (g);
  if (creds == NULL)
    exit (EXIT_FAILURE);

  /* Try to answer from the authentication data. */
  for (i = 0; creds[i] != NULL; ++i) {
    if (STREQ (creds[i], "authname")) {
      reply = auth_data->username;
      len = strlen (reply);
    }
    else if (STREQ (creds[i], "passphrase") ||
             STREQ (creds[i], "noechoprompt")) {
      if (!auth_data->password)
        error (EXIT_FAILURE, 0,
               "test failed: libvirt asked for a password, but auth_data->password == NULL");

      reply = auth_data->password;
      len = strlen (reply);
    }
    else {
      error (EXIT_FAILURE, 0,
             "test failed: libvirt asked for '%s' which is not in creds list\n(This is probably a libvirt bug)",
             creds[i]);
      abort (); /* keeps GCC happy since error(3) is not marked noreturn */
    }

    r = guestfs_set_libvirt_requested_credential (g, i,
                                                  reply, len);
    if (r == -1)
      exit (EXIT_FAILURE);
  }
}
