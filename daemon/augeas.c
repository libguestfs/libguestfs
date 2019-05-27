/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
#include <unistd.h>

#include <augeas.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#define FPRINTF_AUGEAS_ERROR(aug,fs,...)                                \
  do {                                                                  \
    const int code = aug_error (aug);                                   \
    if (code == AUG_ENOMEM)                                             \
      reply_with_error (fs ": augeas out of memory", ##__VA_ARGS__);    \
    else {                                                              \
      const char *aug_err_message = aug_error_message (aug);            \
      const char *aug_err_minor = aug_error_minor_message (aug);        \
      const char *aug_err_details = aug_error_details (aug);            \
      fprintf (stderr, fs ": %s%s%s%s%s", ##__VA_ARGS__,                \
	       aug_err_message,                                         \
	       aug_err_minor ? ": " : "", aug_err_minor ? aug_err_minor : "", \
	       aug_err_details ? ": " : "", aug_err_details ? aug_err_details : ""); \
    }                                                                   \
  } while (0)

int augeas_version;

/* The Augeas handle.  We maintain a single handle per daemon, which
 * is all that is necessary and reduces the complexity of the API
 * considerably.
 */
static augeas *aug = NULL;

void
aug_read_version (void)
{
  CLEANUP_AUG_CLOSE augeas *ah = NULL;
  int r;
  const char *str;
  int major = 0, minor = 0, patch = 0;

  if (augeas_version != 0)
    return;

  /* Optimization: do not load the files nor the lenses, since we are
   * only interested in the version.
   */
  ah = aug_init ("/", NULL, AUG_NO_ERR_CLOSE | AUG_NO_LOAD | AUG_NO_STDINC);
  if (!ah) {
    FPRINTF_AUGEAS_ERROR (ah, "augeas initialization failed");
    return;
  }

  if (aug_error (ah) != AUG_NOERROR) {
    FPRINTF_AUGEAS_ERROR (ah, "aug_init");
    return;
  }

  r = aug_get (ah, "/augeas/version", &str);
  if (r != 1) {
    FPRINTF_AUGEAS_ERROR (ah, "aug_get");
    return;
  }

  r = sscanf (str, "%d.%d.%d", &major, &minor, &patch);
  if (r != 2 && r != 3) {
    fprintf (stderr, "cannot match the version string in '%s'\n", str);
    return;
  }

  if (verbose)
    fprintf (stderr, "augeas version: %d.%d.%d\n", major, minor, patch);

  augeas_version = (major << 16) | (minor << 8) | patch;
}

/* Clean up the augeas handle on daemon exit. */
void aug_finalize (void) __attribute__((destructor));
void
aug_finalize (void)
{
  if (aug) {
    aug_close (aug);
    aug = NULL;
  }
}

#define NEED_AUG(errcode)						\
  do {									\
    if (!aug) {								\
      reply_with_error ("%s: you must call 'aug-init' first to initialize Augeas", __func__); \
      return (errcode);							\
    }									\
  }									\
  while (0)

/* We need to rewrite the root path so it is based at /sysroot. */
int
do_aug_init (const char *root, int flags)
{
  CLEANUP_FREE char *buf = NULL;

  if (aug) {
    aug_close (aug);
    aug = NULL;
  }

  buf = sysroot_path (root);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Pass AUG_NO_ERR_CLOSE so we can display detailed errors. */
  aug = aug_init (buf, NULL, flags | AUG_NO_ERR_CLOSE);

  if (!aug) {
    reply_with_error ("augeas initialization failed");
    return -1;
  }

  if (aug_error (aug) != AUG_NOERROR) {
    AUGEAS_ERROR ("aug_init: %s (flags %d)", root, flags);
    aug_close (aug);
    aug = NULL;
    return -1;
  }

  return 0;
}

int
do_aug_close (void)
{
  NEED_AUG(-1);

  aug_close (aug);
  aug = NULL;

  return 0;
}

int
do_aug_defvar (const char *name, const char *expr)
{
  int r;

  NEED_AUG (-1);

  r = aug_defvar (aug, name, expr);
  if (r == -1) {
    AUGEAS_ERROR ("aug_defvar: %s: %s", name, expr);
    return -1;
  }
  return r;
}

guestfs_int_int_bool *
do_aug_defnode (const char *name, const char *expr, const char *val)
{
  guestfs_int_int_bool *r;
  int i, created;

  NEED_AUG (NULL);

  i = aug_defnode (aug, name, expr, val, &created);
  if (i == -1) {
    AUGEAS_ERROR ("aug_defnode: %s: %s: %s", name, expr, val);
    return NULL;
  }

  r = malloc (sizeof *r);
  if (r == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  r->i = i;
  r->b = created;

  return r;
}

char *
do_aug_get (const char *path)
{
  const char *value = NULL;
  char *v;
  int r;

  NEED_AUG (NULL);

  r = aug_get (aug, path, &value);
  if (r == 0) {
    reply_with_error ("no matching node");
    return NULL;
  }
  if (r != 1) {
    AUGEAS_ERROR ("aug_get: %s", path);
    return NULL;
  }

  /* value can still be NULL here, eg. try with path == "/augeas".
   * I don't understand this case, and it seems to contradict the
   * documentation.
   */
  if (value == NULL) {
    reply_with_error ("Augeas returned NULL match");
    return NULL;
  }

  /* The value is an internal Augeas string, so we must copy it. GC FTW. */
  v = strdup (value);
  if (v == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return v;			/* Caller frees. */
}

int
do_aug_set (const char *path, const char *val)
{
  int r;

  NEED_AUG (-1);

  r = aug_set (aug, path, val);
  if (r == -1) {
    AUGEAS_ERROR ("aug_set: %s: %s", path, val);
    return -1;
  }

  return 0;
}

int
do_aug_clear (const char *path)
{
  int r;

  NEED_AUG (-1);

  r = aug_set (aug, path, NULL);
  if (r == -1) {
    AUGEAS_ERROR ("aug_clear: %s", path);
    return -1;
  }

  return 0;
}

int
do_aug_insert (const char *path, const char *label, int before)
{
  int r;

  NEED_AUG (-1);

  r = aug_insert (aug, path, label, before);
  if (r == -1) {
    AUGEAS_ERROR ("aug_insert: %s: %s [before=%d]", path, label, before);
    return -1;
  }

  return 0;
}

int
do_aug_rm (const char *path)
{
  int r;

  NEED_AUG (-1);

  r = aug_rm (aug, path);
  if (r == -1) {
    AUGEAS_ERROR ("aug_rm: %s", path);
    return -1;
  }

  return r;
}

int
do_aug_mv (const char *src, const char *dest)
{
  int r;

  NEED_AUG (-1);

  r = aug_mv (aug, src, dest);
  if (r == -1) {
    AUGEAS_ERROR ("aug_mv: %s: %s", src, dest);
    return -1;
  }

  return 0;
}

char **
do_aug_match (const char *path)
{
  char **matches = NULL;
  void *vp;
  int r;

  NEED_AUG (NULL);

  r = aug_match (aug, path, &matches);
  if (r == -1) {
    AUGEAS_ERROR ("aug_match: %s", path);
    return NULL;
  }

  /* This returns an array of length r, which we must extend
   * and add a terminating NULL.
   */
  vp = realloc (matches, sizeof (char *) * (r+1));
  if (vp == NULL) {
    reply_with_perror ("realloc");
    free (vp);
    return NULL;
  }
  matches = vp;
  matches[r] = NULL;

  return matches;		/* Caller frees. */
}

int
do_aug_save (void)
{
  NEED_AUG (-1);

  if (aug_save (aug) == -1) {
    AUGEAS_ERROR ("aug_save");
    return -1;
  }

  return 0;
}

int
do_aug_load (void)
{
  NEED_AUG (-1);

  if (aug_load (aug) == -1) {
    AUGEAS_ERROR ("aug_load");
    return -1;
  }

  return 0;
}

/* Simpler version of aug-match, which also sorts the output. */
char **
do_aug_ls (const char *path)
{
  char **matches;
  size_t len;

  NEED_AUG (NULL);

  /* Note that path might also be a previously defined variable
   * (defined with aug_defvar).  See RHBZ#580016.
   */

  len = strlen (path);

  if (len > 1 &&
      (path[len-1] == '/' || path[len-1] == ']' || path[len-1] == '*')) {
    reply_with_error ("don't use aug-ls with a path that ends with / ] *");
    return NULL;
  }

  if (STREQ (path, "/"))
    matches = do_aug_match ("/*");
  else {
    char *buf = NULL;

    if (asprintf (&buf, "%s/*", path) == -1) {
      reply_with_perror ("asprintf");
      return NULL;
    }

    matches = do_aug_match (buf);
    free (buf);
  }

  if (matches == NULL)
    return NULL;		/* do_aug_match has already sent the error */

  sort_strings (matches, guestfs_int_count_strings ((void *) matches));
  return matches;		/* Caller frees. */
}

int
do_aug_setm (const char *base, const char *sub, const char *val)
{
  int r;

  NEED_AUG (-1);

  r = aug_setm (aug, base, sub, val);
  if (r == -1) {
    AUGEAS_ERROR ("aug_setm: %s: %s: %s", base, sub ? sub : "(null)", val);
    return -1;
  }

  return r;
}

char *
do_aug_label (const char *augpath)
{
  int r;
  const char *label;
  char *ret;

  NEED_AUG (NULL);

  r = aug_label (aug, augpath, &label);
  if (r == -1) {
    AUGEAS_ERROR ("aug_label: %s", augpath);
    return NULL;
  }
  if (r == 0) {
    reply_with_error ("no matching nodes found");
    return NULL;
  }

  if (label == NULL) {
    reply_with_error ("internal error: expected label != NULL (r = %d)", r);
    return NULL;
  }

  /* 'label' points to an interior field in the Augeas handle, so
   * we must return a copy.
   */
  ret = strdup (label);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return ret;                   /* caller frees */
}

/* Takes optional arguments, consult optargs_bitmask. */
int
do_aug_transform (const char *lens, const char *file, int remove)
{
  int r;
  int excl = 0; /* add by default */

  NEED_AUG (-1);

  if (optargs_bitmask & GUESTFS_AUG_TRANSFORM_REMOVE_BITMASK)
    excl = remove;

  r = aug_transform (aug, lens, file, excl);
  if (r == -1) {
    AUGEAS_ERROR ("aug_transform: %s: %s: %s", lens, file, excl ? "excl" : "incl");
    return -1;
  }

  return r;
}
