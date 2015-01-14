/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2014 Red Hat Inc.
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

#ifndef GUESTFSD_DAEMON_H
#define GUESTFSD_DAEMON_H

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <errno.h>
#include <unistd.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include "guestfs_protocol.h"

#include "guestfs-internal-all.h"

/* Mountables */

typedef struct {
  mountable_type_t type;
  char *device;
  char *volume;
} mountable_t;

/*-- in guestfsd.c --*/
extern int verbose;

extern int enable_network;

extern int autosync_umount;

extern const char *sysroot;
extern size_t sysroot_len;

extern char *sysroot_path (const char *path);
extern char *sysroot_realpath (const char *path);

extern int is_root_device (const char *device);

extern int xwrite (int sock, const void *buf, size_t len)
  __attribute__((__warn_unused_result__));
extern int xread (int sock, void *buf, size_t len)
  __attribute__((__warn_unused_result__));

extern char *mountable_to_string (const mountable_t *mountable);

/*-- in mount.c --*/

extern int mount_vfs_nochroot (const char *options, const char *vfstype,
                               const mountable_t *mountable,
                               const char *mp, const char *user_mp);

/* Growable strings buffer. */
struct stringsbuf {
  char **argv;
  size_t size;
  size_t alloc;
};
#define DECLARE_STRINGSBUF(v) \
  struct stringsbuf (v) = { .argv = NULL, .size = 0, .alloc = 0 }

/* Append a string to the strings buffer.
 *
 * add_string_nodup: don't copy the string.
 * add_string: copy the string.
 * end_stringsbuf: NULL-terminate the buffer.
 *
 * All functions may fail.  If these functions return -1, then
 * reply_with_* has been called, the strings have been freed and the
 * buffer should no longer be used.
 */
extern int add_string_nodup (struct stringsbuf *sb, char *str);
extern int add_string (struct stringsbuf *sb, const char *str);
extern int add_sprintf (struct stringsbuf *sb, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern int end_stringsbuf (struct stringsbuf *sb);

extern size_t count_strings (char *const *argv);
extern void sort_strings (char **argv, size_t len);
extern void free_strings (char **argv);
extern void free_stringslen (char **argv, size_t len);

extern void sort_device_names (char **argv, size_t len);
extern int compare_device_names (const char *a, const char *b);

/* Concatenate strings, optionally with a separator string between
 * each.  On error, these return NULL but do NOT call reply_with_* nor
 * free anything.
 */
extern char *concat_strings (char *const *argv);
extern char *join_strings (const char *separator, char *const *argv);

extern char **split_lines (char *str);

extern char **empty_list (void);

#define command(out,err,name,...) commandf((out),(err),0,(name),__VA_ARGS__)
#define commandr(out,err,name,...) commandrf((out),(err),0,(name),__VA_ARGS__)
#define commandv(out,err,argv) commandvf((out),(err),0,(argv))
#define commandrv(out,err,argv) commandrvf((out),(err),0,(argv))

#define __external_command __attribute__((__section__(".guestfsd_ext_cmds")))
#define GUESTFSD_EXT_CMD(___ext_cmd_var, ___ext_cmd_str) static const char ___ext_cmd_var[] __external_command = #___ext_cmd_str

#define COMMAND_FLAG_FD_MASK                   (1024-1)
#define COMMAND_FLAG_FOLD_STDOUT_ON_STDERR     1024
#define COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN 2048

extern int commandf (char **stdoutput, char **stderror, int flags,
                     const char *name, ...) __attribute__((sentinel));
extern int commandrf (char **stdoutput, char **stderror, int flags,
                      const char *name, ...) __attribute__((sentinel));
extern int commandvf (char **stdoutput, char **stderror, int flags,
                      char const *const *argv);
extern int commandrvf (char **stdoutput, char **stderror, int flags,
                       char const* const *argv);

extern int is_power_of_2 (unsigned long v);

extern void trim (char *str);

extern char *device_name_translation (const char *device);

extern int parse_btrfsvol (const char *desc, mountable_t *mountable);

extern int prog_exists (const char *prog);

extern void udev_settle (void);

extern int random_name (char *template);

/* This just stops gcc from giving a warning about our custom printf
 * formatters %Q and %R.  See guestfs(3)/EXTENDING LIBGUESTFS for more
 * info about these.  In GCC 4.8.0 the warning is even harder to
 * 'trick', hence the need for the #pragma directives.
 */
#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsuggest-attribute=format"
#endif
static inline int
asprintf_nowarn (char **strp, const char *fmt, ...)
{
  int r;
  va_list args;

  va_start (args, fmt);
  r = vasprintf (strp, fmt, args);
  va_end (args);
  return r;
}
#if defined(__GNUC__) && GUESTFS_GCC_VERSION >= 40800 /* gcc >= 4.8.0 */
#pragma GCC diagnostic pop
#endif

/* Use by the CLEANUP_* macros. */
extern void cleanup_free (void *ptr);
extern void cleanup_free_string_list (void *ptr);
extern void cleanup_unlink_free (void *ptr);
extern void cleanup_close (void *ptr);
extern void cleanup_aug_close (void *ptr);

/*-- in names.c (auto-generated) --*/
extern const char *function_names[];

/*-- in proto.c --*/
extern int proc_nr;
extern int serial;
extern uint64_t progress_hint;
extern uint64_t optargs_bitmask;

/*-- in mount.c --*/
extern int is_root_mounted (void);
extern int is_device_mounted (const char *device);

/*-- in stubs.c (auto-generated) --*/
extern void dispatch_incoming_message (XDR *);
extern guestfs_int_lvm_pv_list *parse_command_line_pvs (void);
extern guestfs_int_lvm_vg_list *parse_command_line_vgs (void);
extern guestfs_int_lvm_lv_list *parse_command_line_lvs (void);

/*-- in optgroups.c (auto-generated) --*/
struct optgroup {
  const char *group;            /* Name of the optional group. */
  int (*available) (void);      /* Function to test availability. */
};
extern struct optgroup optgroups[];

/*-- in available.c --*/
extern int filesystem_available (const char *filesystem);

/*-- in sync.c --*/
/* Use this as a replacement for sync(2). */
extern int sync_disks (void);

/*-- in ext2.c --*/
/* Confirmed this is true up to ext4 from the Linux sources. */
#define EXT2_LABEL_MAX 16
extern int fstype_is_extfs (const char *fstype);

/*-- in blkid.c --*/
extern char *get_blkid_tag (const char *device, const char *tag);

/*-- in lvm.c --*/
extern int lv_canonical (const char *device, char **ret);

/*-- in lvm-filter.c --*/
extern void copy_lvm (void);

/*-- in zero.c --*/
extern void wipe_device_before_mkfs (const char *device);

/*-- in augeas.c --*/
extern void aug_read_version (void);
extern void aug_finalize (void);

/* The version of augeas, saved as:
 * (MAJOR << 16) | (MINOR << 8) | PATCH
 */
extern int augeas_version;
static inline int
augeas_is_version (int major, int minor, int patch)
{
  aug_read_version (); /* Lazy version reading. */
  return augeas_version >= ((major << 16) | (minor << 8) | patch);
}

/*-- hivex.c, journal.c --*/
extern void hivex_finalize (void);
extern void journal_finalize (void);

/*-- in proto.c --*/
extern void main_loop (int sock) __attribute__((noreturn));

/*-- in xattr.c --*/
extern int copy_xattrs (const char *src, const char *dest);

/*-- in xfs.c --*/
/* Documented in xfs_admin(8). */
#define XFS_LABEL_MAX 12

/*-- in btrfs.c --*/
extern char *btrfs_get_label (const char *device);

/* ordinary daemon functions use these to indicate errors
 * NB: you don't need to prefix the string with the current command,
 * it is added automatically by the client-side RPC stubs.
 */
extern void reply_with_error_errno (int err, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void reply_with_perror_errno (int err, const char *fs, ...)
  __attribute__((format (printf,2,3)));
#define reply_with_error(...) reply_with_error_errno(0, __VA_ARGS__)
#define reply_with_perror(...) reply_with_perror_errno(errno, __VA_ARGS__)
#define reply_with_unavailable_feature(feature) \
  reply_with_error_errno (ENOTSUP, \
     "feature '%s' is not available in this\n" \
     "build of libguestfs.  Read 'AVAILABILITY' in the guestfs(3) man page for\n" \
     "how to check for the availability of features.", \
     feature)

/* daemon functions that receive files (FileIn) should call
 * receive_file for each FileIn parameter.
 */
typedef int (*receive_cb) (void *opaque, const void *buf, size_t len);
extern int receive_file (receive_cb cb, void *opaque);

/* daemon functions that receive files (FileIn) can call this
 * to cancel incoming transfers (eg. if there is a local error).
 */
extern int cancel_receive (void);

/* daemon functions that return files (FileOut) should call
 * reply, then send_file_* for each FileOut parameter.
 * Note max write size if GUESTFS_MAX_CHUNK_SIZE.
 */
extern int send_file_write (const void *buf, size_t len);
extern int send_file_end (int cancel);

/* only call this if there is a FileOut parameter */
extern void reply (xdrproc_t xdrp, char *ret);

/* Notify progress to caller.  This function is self-rate-limiting so
 * you can call it as often as necessary.  Actions which call this
 * should add 'Progress' note in generator.
 */
extern void notify_progress (uint64_t position, uint64_t total);

/* Pulse mode progress messages.
 *
 * Call pulse_mode_start to start sending progress messages.
 *
 * Call pulse_mode_end along the ordinary exit path (ie. before a
 * reply message is sent).
 *
 * Call pulse_mode_cancel along all error paths *before* any reply is
 * sent.  pulse_mode_cancel does not modify errno, so it is safe to
 * call it before reply_with_perror.
 *
 * Pulse mode and ordinary notify_progress must not be mixed.
 */
extern void pulse_mode_start (void);
extern void pulse_mode_end (void);
extern void pulse_mode_cancel (void);

/* Send a progress message without rate-limiting.  This is just
 * for debugging - DON'T use it in regular code!
 */
extern void notify_progress_no_ratelimit (uint64_t position, uint64_t total, const struct timeval *now);

/* Return true iff the buffer is all zero bytes.
 *
 * Note that gcc is smart enough to optimize this properly:
 * http://stackoverflow.com/questions/1493936/faster-means-of-checking-for-an-empty-buffer-in-c/1493989#1493989
 */
static inline int
is_zero (const char *buffer, size_t size)
{
  size_t i;

  for (i = 0; i < size; ++i) {
    if (buffer[i] != 0)
      return 0;
  }

  return 1;
}

/* Helper for building up short lists of arguments.  Your code has to
 * define MAX_ARGS to a suitable value.
 */
#define ADD_ARG(argv,i,v)                                               \
  do {                                                                  \
    if ((i) >= MAX_ARGS) {                                              \
      fprintf (stderr, "%s: %d: internal error: exceeded MAX_ARGS (%zu) when constructing the command line\n", __FILE__, __LINE__, (size_t) MAX_ARGS); \
      abort ();                                                         \
    }                                                                   \
    (argv)[(i)++] = (v);                                                \
  } while (0)

/* Helper for functions that need a root filesystem mounted.
 * NB. Cannot be used for FileIn functions.
 */
#define NEED_ROOT(cancel_stmt,fail_stmt)                                \
  do {									\
    if (!is_root_mounted ()) {						\
      cancel_stmt;                                                      \
      reply_with_error ("%s: you must call 'mount' first to mount the root filesystem", __func__); \
      fail_stmt;							\
    }									\
  }									\
  while (0)

/* Helper for functions that need an argument ("path") that is absolute.
 * NB. Cannot be used for FileIn functions.
 */
#define ABS_PATH(path,cancel_stmt,fail_stmt)                            \
  do {									\
    if ((path)[0] != '/') {						\
      cancel_stmt;                                                      \
      reply_with_error ("%s: path must start with a / character", __func__); \
      fail_stmt;							\
    }									\
  } while (0)

/* NB:
 * (1) You must match CHROOT_IN and CHROOT_OUT even along error paths.
 * (2) You must not change directory!  cwd must always be "/", otherwise
 *     we can't escape our own chroot.
 * (3) All paths specified must be absolute.
 * (4) Neither macro affects errno.
 */
#define CHROOT_IN				\
  do {						\
    if (sysroot_len > 0) {                      \
      int __old_errno = errno;			\
      if (chroot (sysroot) == -1)               \
        perror ("CHROOT_IN: sysroot");		\
      errno = __old_errno;			\
    }                                           \
  } while (0)
#define CHROOT_OUT				\
  do {						\
    if (sysroot_len > 0) {                      \
      int __old_errno = errno;			\
      if (chroot (".") == -1)			\
        perror ("CHROOT_OUT: .");               \
      errno = __old_errno;			\
    }                                           \
  } while (0)

/* Marks functions which are not implemented.
 * NB. Cannot be used for FileIn functions.
 */
#define XXX_NOT_IMPL(errcode)						\
  do {									\
    reply_with_error ("%s: function not implemented", __func__);	\
    return (errcode);							\
  }									\
  while (0)

/* Marks functions which are not supported. */
#define NOT_SUPPORTED(errcode,...)                      \
    do {                                                \
      reply_with_error_errno (ENOTSUP, __VA_ARGS__);    \
      return (errcode);                                 \
    }                                                   \
    while (0)

/* Calls reply_with_error, but includes the Augeas error details. */
#define AUGEAS_ERROR(fs,...)                                            \
  do {                                                                  \
    int code = aug_error (aug);                                         \
    if (code == AUG_ENOMEM)                                             \
      reply_with_error (fs ": augeas out of memory", ##__VA_ARGS__);    \
    else {                                                              \
      const char *message = aug_error_message (aug);                    \
      const char *minor = aug_error_minor_message (aug);                \
      const char *details = aug_error_details (aug);                    \
      reply_with_error (fs ": %s%s%s%s%s", ##__VA_ARGS__,               \
                          message,                                      \
                          minor ? ": " : "", minor ? minor : "",        \
                          details ? ": " : "", details ? details : ""); \
    }                                                                   \
  } while (0)

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE __attribute__((cleanup(cleanup_free)))
#define CLEANUP_FREE_STRING_LIST                        \
    __attribute__((cleanup(cleanup_free_string_list)))
#define CLEANUP_UNLINK_FREE __attribute__((cleanup(cleanup_unlink_free)))
#define CLEANUP_CLOSE __attribute__((cleanup(cleanup_close)))
#define CLEANUP_AUG_CLOSE __attribute__((cleanup(cleanup_aug_close)))
#else
#define CLEANUP_FREE
#define CLEANUP_FREE_STRING_LIST
#define CLEANUP_UNLINK_FREE
#define CLEANUP_CLOSE
#define CLEANUP_AUG_CLOSE
#endif

#endif /* GUESTFSD_DAEMON_H */
