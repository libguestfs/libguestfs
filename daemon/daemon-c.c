/* guestfs-inspection
 * Copyright (C) 2017 Red Hat Inc.
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

#include <caml/alloc.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>

#include "daemon.h"
#include "daemon-c.h"

/* Convert an OCaml exception to a reply_with_error_errno call
 * as best we can.
 */
void
guestfs_int_daemon_exn_to_reply_with_error (const char *func, value exn)
{
  const char *exn_name;

  /* This is not the official way to do this, but I could not get the
   * official way to work, and this way does work.  See
   * http://caml.inria.fr/pub/ml-archives/caml-list/2006/05/097f63cfb39a80418f95c70c3c520aa8.en.html
   * http://caml.inria.fr/pub/ml-archives/caml-list/2009/06/797e2f797f57b8ea2a2c0e431a2df312.en.html
   */
  if (Tag_val (Field (exn, 0)) == String_tag)
    /* For End_of_file and a few other constant exceptions. */
    exn_name = String_val (Field (exn, 0));
  else
    /* For most exceptions. */
    exn_name = String_val (Field (Field (exn, 0), 0));

  if (verbose)
    fprintf (stderr, "ocaml_exn: '%s' raised '%s' exception\n",
             func, exn_name);

  if (STREQ (exn_name, "Unix.Unix_error")) {
    int errcode = code_of_unix_error (Field (exn, 1));
    reply_with_perror_errno (errcode, "%s: %s",
                             String_val (Field (exn, 2)),
                             String_val (Field (exn, 3)));
  }
  else if (STREQ (exn_name, "Failure"))
    reply_with_error ("%s", String_val (Field (exn, 1)));
  else if (STREQ (exn_name, "Sys_error"))
    reply_with_error ("%s", String_val (Field (exn, 1)));
  else if (STREQ (exn_name, "Invalid_argument"))
    reply_with_error ("invalid argument: %s", String_val (Field (exn, 1)));
  else if (STREQ (exn_name, "Augeas.Error")) {
    const char *message = String_val (Field (exn, 3));
    const char *minor = String_val (Field (exn, 4));
    const char *details = String_val (Field (exn, 5));
    reply_with_error ("augeas error: %s%s%s%s%s",
                      message,
                      minor ? ": " : "", minor ? minor : "",
                      details ? ": " : "", details ? details : "");
  }
  else if (STREQ (exn_name, "PCRE.Error")) {
    value pair = Field (exn, 1);
    reply_with_error ("PCRE error: %s (PCRE error code: %d)",
                      String_val (Field (pair, 0)),
                      Int_val (Field (pair, 1)));
  }
  else
    reply_with_error ("internal error: %s: unhandled exception thrown: %s",
                      func, exn_name);
}

/* Implement String (Mountable, _) parameter. */
value
guestfs_int_daemon_copy_mountable (const mountable_t *mountable)
{
  CAMLparam0 ();
  CAMLlocal4 (r, typev, devicev, volumev);

  switch (mountable->type) {
  case MOUNTABLE_DEVICE:
    typev = Val_int (0); /* MountableDevice */
    break;
  case MOUNTABLE_PATH:
    typev = Val_int (1); /* MountablePath */
    break;
  case MOUNTABLE_BTRFSVOL:
    volumev = caml_copy_string (mountable->volume);
    typev = caml_alloc (1, 0); /* MountableBtrfsVol */
    Store_field (typev, 0, volumev);
  }

  devicev = caml_copy_string (mountable->device);

  r = caml_alloc_tuple (2);
  Store_field (r, 0, typev);
  Store_field (r, 1, devicev);

  CAMLreturn (r);
}

/* Implement RStringList. */
char **
guestfs_int_daemon_return_string_list (value retv)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  value v;

  while (retv != Val_int (0)) {
    v = Field (retv, 0);
    if (add_string (&ret, String_val (v)) == -1)
      return NULL;
    retv = Field (retv, 1);
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret); /* caller frees */
}

/* Implement RString (RMountable, _). */
char *
guestfs_int_daemon_return_string_mountable (value retv)
{
  value typev = Field (retv, 0);
  value devicev = Field (retv, 1);
  value subvolv;
  char *ret;

  if (Is_long (typev)) {      /* MountableDevice or MountablePath */
    ret = strdup (String_val (devicev));
    if (ret == NULL)
      reply_with_perror ("strdup");
    return ret;
  }
  else {                      /* MountableBtrfsVol of subvol */
    subvolv = Field (typev, 0);
    if (asprintf (&ret, "btrfsvol:%s/%s",
                        String_val (devicev), String_val (subvolv)) == -1)
      reply_with_perror ("asprintf");
    return ret;
  }
}

/* Implement RStringList (RMountable, _). */
char **
guestfs_int_daemon_return_string_mountable_list (value retv)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  value v;
  char *m;

  while (retv != Val_int (0)) {
    v = Field (retv, 0);
    m = guestfs_int_daemon_return_string_mountable (v);
    if (m == NULL)
      return NULL;
    if (add_string_nodup (&ret, m) == -1)
      return NULL;
    retv = Field (retv, 1);
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret); /* caller frees */
}

/* Implement RHashtable (RPlainString, RPlainString, _). */
char **
guestfs_int_daemon_return_hashtable_string_string (value retv)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  value v, sv;

  while (retv != Val_int (0)) {
    v = Field (retv, 0);        /* (string, string) */
    sv = Field (v, 0);          /* string */
    if (add_string (&ret, String_val (sv)) == -1)
      return NULL;
    sv = Field (v, 1);          /* string */
    if (add_string (&ret, String_val (sv)) == -1)
      return NULL;
    retv = Field (retv, 1);
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret); /* caller frees */
}

/* Implement RHashtable (RMountable, RPlainString, _). */
char **
guestfs_int_daemon_return_hashtable_mountable_string (value retv)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  value v, mv, sv;
  char *m;

  while (retv != Val_int (0)) {
    v = Field (retv, 0);        /* (Mountable.t, string) */
    mv = Field (v, 0);          /* Mountable.t */
    m = guestfs_int_daemon_return_string_mountable (mv);
    if (m == NULL)
      return NULL;
    if (add_string_nodup (&ret, m) == -1)
      return NULL;
    sv = Field (v, 1);          /* string */
    if (add_string (&ret, String_val (sv)) == -1)
      return NULL;
    retv = Field (retv, 1);
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret); /* caller frees */
}

/* Implement RHashtable (RPlainString, RMountable, _). */
char **
guestfs_int_daemon_return_hashtable_string_mountable (value retv)
{
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  value sv, v, mv;
  char *m;

  while (retv != Val_int (0)) {
    v = Field (retv, 0);        /* (string, Mountable.t) */
    sv = Field (v, 0);          /* string */
    if (add_string (&ret, String_val (sv)) == -1)
      return NULL;
    mv = Field (v, 1);          /* Mountable.t */
    m = guestfs_int_daemon_return_string_mountable (mv);
    if (m == NULL)
      return NULL;
    if (add_string_nodup (&ret, m) == -1)
      return NULL;
    retv = Field (retv, 1);
  }

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret); /* caller frees */
}
