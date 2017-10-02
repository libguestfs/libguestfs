/* libguestfs OCaml tools common code
 * Copyright (C) 2009-2017 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <errno.h>
#include <sys/types.h>

#ifdef HAVE_SYS_STATVFS_H
#include <sys/statvfs.h>
#endif

#if MAJOR_IN_MKDEV
#include <sys/mkdev.h>
#elif MAJOR_IN_SYSMACROS
#include <sys/sysmacros.h>
/* else it's in sys/types.h, included above */
#endif

#ifdef HAVE_WINDOWS_H
#include <windows.h>
#endif

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

extern value guestfs_int_mllib_dev_t_makedev (value majv, value minv);
extern value guestfs_int_mllib_dev_t_major (value devv);
extern value guestfs_int_mllib_dev_t_minor (value devv);
extern value guestfs_int_mllib_unsetenv (value strv);
extern int guestfs_int_mllib_exit (value rv) __attribute__((noreturn));
extern value guestfs_int_mllib_fnmatch (value patternv, value strv, value flagsv);
extern value guestfs_int_mllib_sync (value unitv);
extern value guestfs_int_mllib_fsync_file (value filenamev);
extern value guestfs_int_mllib_mkdtemp (value val_pattern);
extern value guestfs_int_mllib_realpath (value pathv);
extern value guestfs_int_mllib_statvfs_statvfs (value pathv);

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_dev_t_makedev (value majv, value minv)
{
  return Val_int (makedev (Int_val (majv), Int_val (minv)));
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_dev_t_major (value devv)
{
  return Val_int (major (Int_val (devv)));
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_dev_t_minor (value devv)
{
  return Val_int (minor (Int_val (devv)));
}

/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_unsetenv (value strv)
{
  unsetenv (String_val (strv));
  return Val_unit;
}

/* NB: This is a "noalloc" call. */
int
guestfs_int_mllib_exit (value rv)
{
  _exit (Int_val (rv));
}

/* NB: These flags must appear in the same order as unix_utils.ml */
static int flags[] = {
  FNM_NOESCAPE,
  FNM_PATHNAME,
  FNM_PERIOD,
  FNM_FILE_NAME,
  FNM_LEADING_DIR,
  FNM_CASEFOLD,
};

value
guestfs_int_mllib_fnmatch (value patternv, value strv, value flagsv)
{
  CAMLparam3 (patternv, strv, flagsv);
  int f = 0, r;

  /* Convert flags to bitmask. */
  while (flagsv != Val_int (0)) {
    f |= flags[Int_val (Field (flagsv, 0))];
    flagsv = Field (flagsv, 1);
  }

  r = fnmatch (String_val (patternv), String_val (strv), f);

  if (r == 0)
    CAMLreturn (Val_true);
  else if (r == FNM_NOMATCH)
    CAMLreturn (Val_false);
  else {
    /* XXX The fnmatch specification doesn't mention what errors can
     * be returned by fnmatch.  Assume they are errnos for now.
     */
    unix_error (errno, (char *) "fnmatch", patternv);
  }
}


/* NB: This is a "noalloc" call. */
value
guestfs_int_mllib_sync (value unitv)
{
  sync ();
  return Val_unit;
}

/* Flush all writes associated with the named file to the disk.
 *
 * Note the wording in the SUS definition:
 *
 * "The fsync() function forces all currently queued I/O operations
 * associated with the file indicated by file descriptor fildes to the
 * synchronised I/O completion state."
 *
 * http://pubs.opengroup.org/onlinepubs/007908775/xsh/fsync.html
 */
value
guestfs_int_mllib_fsync_file (value filenamev)
{
  CAMLparam1 (filenamev);
  const char *filename = String_val (filenamev);
  int fd, err;

  /* Note to do fsync you have to open for write. */
  fd = open (filename, O_RDWR);
  if (fd == -1)
    unix_error (errno, (char *) "open", filenamev);

  if (fsync (fd) == -1) {
    err = errno;
    close (fd);
    unix_error (err, (char *) "fsync", filenamev);
  }

  if (close (fd) == -1)
    unix_error (errno, (char *) "close", filenamev);

  CAMLreturn (Val_unit);
}

value
guestfs_int_mllib_mkdtemp (value val_pattern)
{
  CAMLparam1 (val_pattern);
  CAMLlocal1 (rv);
  char *pattern, *ret;

  pattern = strdup (String_val (val_pattern));
  if (pattern == NULL)
    unix_error (errno, (char *) "strdup", val_pattern);

  ret = mkdtemp (pattern);
  if (ret == NULL)
    unix_error (errno, (char *) "mkdtemp", val_pattern);

  rv = caml_copy_string (ret);
  free (pattern);

  CAMLreturn (rv);
}

value
guestfs_int_mllib_realpath (value pathv)
{
  CAMLparam1 (pathv);
  CAMLlocal1 (rv);
  char *r;

  r = realpath (String_val (pathv), NULL);
  if (r == NULL)
    unix_error (errno, (char *) "realpath", pathv);

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
}

value
guestfs_int_mllib_statvfs_statvfs (value pathv)
{
  CAMLparam1 (pathv);
  int64_t f_bsize;
  int64_t f_frsize;
  int64_t f_blocks;
  int64_t f_bfree;
  int64_t f_bavail;
  int64_t f_files;
  int64_t f_ffree;
  int64_t f_favail;
  int64_t f_fsid;
  int64_t f_flag;
  int64_t f_namemax;
  CAMLlocal2 (rv, v);

#ifdef HAVE_STATVFS
  struct statvfs buf;

  if (statvfs (String_val (pathv), &buf) == -1)
    unix_error (errno, (char *) "statvfs", pathv);

  f_bsize = buf.f_bsize;
  f_frsize = buf.f_frsize;
  f_blocks = buf.f_blocks;
  f_bfree = buf.f_bfree;
  f_bavail = buf.f_bavail;
  f_files = buf.f_files;
  f_ffree = buf.f_ffree;
  f_favail = buf.f_favail;
  f_fsid = buf.f_fsid;
  f_flag = buf.f_flag;
  f_namemax = buf.f_namemax;

#else /* !HAVE_STATVFS */
#  if WIN32
  ULONGLONG free_bytes_available; /* for user - similar to bavail */
  ULONGLONG total_number_of_bytes;
  ULONGLONG total_number_of_free_bytes; /* for everyone - bfree */

  if (!GetDiskFreeSpaceEx (String_val (pathv),
                           (PULARGE_INTEGER) &free_bytes_available,
                           (PULARGE_INTEGER) &total_number_of_bytes,
                           (PULARGE_INTEGER) &total_number_of_free_bytes))
    unix_error (EIO, (char *) "statvfs: GetDiskFreeSpaceEx", pathv);

  /* XXX I couldn't determine how to get block size.  MSDN has a
   * unhelpful hard-coded list here:
   *   http://support.microsoft.com/kb/140365
   * but this depends on the filesystem type, the size of the disk and
   * the version of Windows.  So this code assumes the disk is NTFS
   * and the version of Windows is >= Win2K.
   */
  if (total_number_of_bytes < UINT64_C (16) * 1024 * 1024 * 1024 * 1024)
    f_bsize = 4096;
  else if (total_number_of_bytes < UINT64_C (32) * 1024 * 1024 * 1024 * 1024)
    f_bsize = 8192;
  else if (total_number_of_bytes < UINT64_C (64) * 1024 * 1024 * 1024 * 1024)
    f_bsize = 16384;
  else if (total_number_of_bytes < UINT64_C (128) * 1024 * 1024 * 1024 * 1024)
    f_bsize = 32768;
  else
    f_bsize = 65536;

  /* As with stat, -1 indicates a field is not known. */
  f_frsize = ret->bsize;
  f_blocks = total_number_of_bytes / ret->bsize;
  f_bfree = total_number_of_free_bytes / ret->bsize;
  f_bavail = free_bytes_available / ret->bsize;
  f_files = -1;
  f_ffree = -1;
  f_favail = -1;
  f_fsid = -1;
  f_flag = -1;
  f_namemax = FILENAME_MAX;

#  else /* !WIN32 */
#error "no statvfs or equivalent function available"
#  endif /* !WIN32 */
#endif /* !HAVE_STATVFS */

  /* Construct the return struct. */
  rv = caml_alloc (11, 0);
  v = caml_copy_int64 (f_bsize);
  Store_field (rv, 0, v);
  v = caml_copy_int64 (f_frsize);
  Store_field (rv, 1, v);
  v = caml_copy_int64 (f_blocks);
  Store_field (rv, 2, v);
  v = caml_copy_int64 (f_bfree);
  Store_field (rv, 3, v);
  v = caml_copy_int64 (f_bavail);
  Store_field (rv, 4, v);
  v = caml_copy_int64 (f_files);
  Store_field (rv, 5, v);
  v = caml_copy_int64 (f_ffree);
  Store_field (rv, 6, v);
  v = caml_copy_int64 (f_favail);
  Store_field (rv, 7, v);
  v = caml_copy_int64 (f_fsid);
  Store_field (rv, 8, v);
  v = caml_copy_int64 (f_flag);
  Store_field (rv, 9, v);
  v = caml_copy_int64 (f_namemax);
  Store_field (rv, 10, v);

  CAMLreturn (rv);
}
