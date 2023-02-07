/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
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

#ifndef GUESTFSD_STUBS_MACROS_H
#define GUESTFSD_STUBS_MACROS_H

/* Some macros to make resolving devices easier.  These used to
 * be available in daemon.h but now they are only used by stubs.
 */

/* All functions that need an argument that is a device or partition name
 * must call this macro.  It checks that the device exists and does
 * device name translation (described in the guestfs(3) manpage).
 * Note that the "path" argument may be modified.
 */
#define RESOLVE_DEVICE(path,path_out,is_filein)                         \
  do {									\
    (path_out) = device_name_translation ((path));                      \
    if ((path_out) == NULL) {                                           \
      const int err = errno;                                            \
      if (is_filein) cancel_receive ();                                 \
      errno = err;                                                      \
      reply_with_perror ("%s: %s", __func__, path);                     \
      return;							        \
    }                                                                   \
    if (!is_device_parameter ((path_out))) {                            \
      if (is_filein) cancel_receive ();                                 \
      reply_with_error ("%s: %s: expecting a device name", __func__, (path)); \
      return;							        \
    }									\
  } while (0)

/* All functions that take a mountable argument must call this macro.
 * It parses the mountable into a mountable_t, ensures any
 * underlying device exists, and does device name translation
 * (described in the guestfs(3) manpage).
 *
 * Note that the "string" argument may be modified.
 */
#define RESOLVE_MOUNTABLE(string,mountable,is_filein)                   \
  do {                                                                  \
    if (STRPREFIX ((string), "btrfsvol:")) {                            \
      if (parse_btrfsvol ((string) + strlen ("btrfsvol:"), &(mountable)) == -1)\
      {                                                                 \
        if (is_filein) cancel_receive ();                               \
        reply_with_error ("%s: %s: expecting a btrfs volume",           \
                          __func__, (string));                          \
        return;                                                         \
      }                                                                 \
    }                                                                   \
    else {                                                              \
      (mountable).type = MOUNTABLE_DEVICE;                              \
      (mountable).device = NULL;                                        \
      (mountable).volume = NULL;                                        \
      RESOLVE_DEVICE ((string), (mountable).device, (is_filein));       \
    }                                                                   \
  } while (0)

/* Helper for functions which need either an absolute path in the
 * mounted filesystem, OR a /dev/ device which exists.
 *
 * NB: Functions which mix filenames and device paths should be
 * avoided, and existing functions should be deprecated.  This is
 * because we intend in future to make device parameters a distinct
 * type from filenames.
 */
#define REQUIRE_ROOT_OR_RESOLVE_DEVICE(path,path_out,is_filein)         \
  do {									\
    if (is_device_parameter ((path)))                                   \
      RESOLVE_DEVICE ((path), (path_out), (is_filein));                 \
    else {								\
      NEED_ROOT ((is_filein), return);                                  \
      ABS_PATH ((path), (is_filein), return);                           \
      (path_out) = strdup ((path));                                     \
      if ((path_out) == NULL) {                                         \
        if (is_filein) cancel_receive ();                               \
        reply_with_perror ("strdup");                                   \
        return;                                                         \
      }                                                                 \
    }									\
  } while (0)

/* Helper for functions which need either an absolute path in the
 * mounted filesystem, OR a valid mountable description.
 */
#define REQUIRE_ROOT_OR_RESOLVE_MOUNTABLE(string, mountable, is_filein) \
  do {                                                                  \
    if (is_device_parameter ((string)) || (string)[0] != '/') {         \
      RESOLVE_MOUNTABLE ((string), (mountable), (is_filein));           \
    }                                                                   \
    else {                                                              \
      NEED_ROOT ((is_filein), return);                                  \
      /* NB: It's a path, not a device. */                              \
      (mountable).type = MOUNTABLE_PATH;                                \
      (mountable).device = strdup ((string));                           \
      (mountable).volume = NULL;                                        \
      if ((mountable).device == NULL) {                                 \
        if (is_filein) cancel_receive ();                               \
        reply_with_perror ("strdup");                                   \
        return;                                                         \
      }                                                                 \
    }                                                                   \
  } while (0)                                                           \

#endif /* GUESTFSD_STUBS_MACROS_H */
