/* libguestfs - the guestfsd daemon
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
#include <limits.h>
#include <unistd.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#if defined(HAVE_ACL)

#include <sys/types.h>
#include <sys/acl.h>

int
optgroup_acl_available (void)
{
  return 1;
}

char *
do_acl_get_file (const char *path, const char *acltype)
{
  acl_type_t t;
  acl_t acl;
  char *r, *ret;

  if (STREQ (acltype, "access"))
    t = ACL_TYPE_ACCESS;
  else if (STREQ (acltype, "default"))
    t = ACL_TYPE_DEFAULT;
  else {
    reply_with_error ("invalid acltype parameter: %s", acltype);
    return NULL;
  }

  CHROOT_IN;
  acl = acl_get_file (path, t);
  CHROOT_OUT;

  if (acl == NULL) {
    reply_with_perror ("%s", path);
    return NULL;
  }

  r = acl_to_text (acl, NULL);
  if (r == NULL) {
    reply_with_perror ("acl_to_text");
    acl_free (acl);
    return NULL;
  }

  acl_free (acl);

  /* 'r' is not an ordinary pointer that can be freed with free(3)!
   * In the current implementation of libacl, if you try to do that it
   * will segfault.  We have to duplicate this into an ordinary
   * buffer, then call acl_free (r).
   */
  ret = strdup (r);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    acl_free (r);
    return NULL;
  }
  acl_free (r);

  return ret;                   /* caller frees */
}

int
do_acl_set_file (const char *path, const char *acltype, const char *aclstr)
{
  acl_type_t t;
  acl_t acl;
  int r;

  if (STREQ (acltype, "access"))
    t = ACL_TYPE_ACCESS;
  else if (STREQ (acltype, "default"))
    t = ACL_TYPE_DEFAULT;
  else {
    reply_with_error ("invalid acltype parameter: %s", acltype);
    return -1;
  }

  acl = acl_from_text (aclstr);
  if (acl == NULL) {
    reply_with_perror ("could not parse acl string: %s: acl_from_text", aclstr);
    return -1;
  }

  CHROOT_IN;
  r = acl_set_file (path, t, acl);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    acl_free (acl);
    return -1;
  }

  acl_free (acl);

  return 0;
}

int
do_acl_delete_def_file (const char *dir)
{
  int r;

  CHROOT_IN;
  r = acl_delete_def_file (dir);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", dir);
    return -1;
  }

  return 0;
}

#else /* no acl library */

OPTGROUP_ACL_NOT_AVAILABLE

#endif /* no acl library */
