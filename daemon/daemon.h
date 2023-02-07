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

#ifndef GUESTFSD_DAEMON_H
#define GUESTFSD_DAEMON_H

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include "guestfs_protocol.h"

#include "cleanups.h"
#include "guestfs-utils.h"

#include "guestfs-internal-all.h"

#include "structs-cleanups.h"
#include "command.h"

struct stringsbuf {
  char **argv;
  size_t size;
  size_t alloc;
};

typedef struct {
  mountable_type_t type;
  char *device;
  char *volume;
} mountable_t;

/* utils.c */
extern int verbose;
extern int enable_network;
extern int autosync_umount;
extern int test_mode;
extern const char *sysroot;
extern size_t sysroot_len;
extern dev_t root_device;

extern void shell_quote (const char *str, FILE *fp);
extern char *sysroot_path (const char *path);
extern char *sysroot_realpath (const char *path);
extern void sysroot_shell_quote (const char *path, FILE *fp);
extern int is_root_device (const char *device);
extern int is_device_parameter (const char *device);
extern int xwrite (int sock, const void *buf, size_t len)
  __attribute__((__warn_unused_result__));
extern int xread (int sock, void *buf, size_t len)
  __attribute__((__warn_unused_result__));
extern void sort_strings (char **argv, size_t len);
extern void free_stringslen (char **argv, size_t len);
extern char **take_stringsbuf (struct stringsbuf *sb);
extern void free_stringsbuf (struct stringsbuf *sb);
extern struct stringsbuf split_lines_sb (char *str);
extern char **split_lines (char *str);
extern char **empty_list (void);
extern char **filter_list (bool (*p) (const char *), char **strs);
extern int is_power_of_2 (unsigned long v);
extern void trim (char *str);
extern int parse_btrfsvol (const char *desc, mountable_t *mountable);
extern int prog_exists (const char *prog);
extern void udev_settle_file (const char *file);
extern void udev_settle (void);
extern int random_name (char *template);
extern char *get_random_uuid (void);
extern char *make_exclude_from_file (const char *function, char *const *excludes);
extern char *read_whole_file (const char *filename, size_t *size_r);

/* mountable functions (in utils.c) */
extern char *mountable_to_string (const mountable_t *mountable);
extern void cleanup_free_mountable (mountable_t *mountable);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE_MOUNTABLE __attribute__((cleanup(cleanup_free_mountable)))
#else
#define CLEANUP_FREE_MOUNTABLE
#endif

/* cleanups.c */
/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */
extern void cleanup_aug_close (void *ptr);
extern void cleanup_free_stringsbuf (void *ptr);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_AUG_CLOSE __attribute__((cleanup(cleanup_aug_close)))
#define CLEANUP_FREE_STRINGSBUF __attribute__((cleanup(cleanup_free_stringsbuf)))
#else
#define CLEANUP_AUG_CLOSE
#define CLEANUP_FREE_STRINGSBUF
#endif

/* mount.c */
extern int is_root_mounted (void);
extern int is_device_mounted (const char *device);

/* stringsbuf.c: growable strings buffer. */
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


/* names.c (auto-generated) */
extern const char *function_names[];

/* proto.c */
extern int proc_nr;
extern int serial;
extern uint64_t progress_hint;
extern uint64_t optargs_bitmask;

extern void main_loop (int sock) __attribute__((noreturn));

/* Ordinary daemon functions use these to indicate errors.
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

/* Daemon functions that receive files (FileIn) should call
 * receive_file for each FileIn parameter.
 */
typedef int (*receive_cb) (void *opaque, const void *buf, size_t len);
extern int receive_file (receive_cb cb, void *opaque);

/* Daemon functions that receive files (FileIn) can call this
 * to cancel incoming transfers (eg. if there is a local error).
 */
extern int cancel_receive (void);

/* Daemon functions that return files (FileOut) should call
 * reply, then send_file_* for each FileOut parameter.
 * Note max write size if GUESTFS_MAX_CHUNK_SIZE.
 */
extern int send_file_write (const void *buf, size_t len);
extern int send_file_end (int cancel);

/* Only call this if there is a FileOut parameter. */
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

/* device-name-translation.c */
extern char *device_name_translation (const char *device);
extern void device_name_translation_init (void);
extern char *reverse_device_name_translation (const char *device);

/* stubs.c (auto-generated) */
extern void dispatch_incoming_message (XDR *);
extern guestfs_int_lvm_pv_list *parse_command_line_pvs (void);
extern guestfs_int_lvm_vg_list *parse_command_line_vgs (void);
extern guestfs_int_lvm_lv_list *parse_command_line_lvs (void);

/* optgroups.c (auto-generated) */
struct optgroup {
  const char *group;            /* Name of the optional group. */
  int (*available) (void);      /* Function to test availability. */
};
extern struct optgroup optgroups[];

/* available.c */
extern int filesystem_available (const char *filesystem);

/* sync.c */
/* Use this as a replacement for sync(2). */
extern int sync_disks (void);

/* ext2.c */
/* Confirmed this is true up to ext4 from the Linux sources. */
#define EXT2_LABEL_MAX 16
extern int fstype_is_extfs (const char *fstype);
extern int ext_set_uuid_random (const char *device);
extern int64_t ext_minimum_size (const char *device);

/* blkid.c */
extern char *get_blkid_tag (const char *device, const char *tag);

/* lvm.c */
extern int lv_canonical (const char *device, char **ret);

/* zero.c */
extern void wipe_device_before_mkfs (const char *device);

/* augeas.c */
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

/* hivex.c */
extern void hivex_finalize (void);

/* journal.c */
extern void journal_finalize (void);

/* xattr.c */
extern int copy_xattrs (const char *src, const char *dest);

/* xfs.c */
/* Documented in xfs_admin(8). */
#define XFS_LABEL_MAX 12
extern int xfs_set_uuid (const char *device, const char *uuid);
extern int xfs_set_uuid_random (const char *device);
extern int xfs_set_label (const char *device, const char *label);
extern int64_t xfs_minimum_size (const char *path);

/* debug-bmap.c */
extern char *debug_bmap (const char *subcmd, size_t argc, char *const *const argv);
extern char *debug_bmap_file (const char *subcmd, size_t argc, char *const *const argv);
extern char *debug_bmap_device (const char *subcmd, size_t argc, char *const *const argv);

/* btrfs.c */
extern char *btrfs_get_label (const char *device);
extern int btrfs_set_label (const char *device, const char *label);
extern int btrfs_set_uuid (const char *device, const char *uuid);
extern int btrfs_set_uuid_random (const char *device);
extern int64_t btrfs_minimum_size (const char *path);

/* ntfs.c */
extern char *ntfs_get_label (const char *device);
extern int ntfs_set_label (const char *device, const char *label);
extern int64_t ntfs_minimum_size (const char *device);

/* swap.c */
extern int swap_set_uuid (const char *device, const char *uuid);
extern int swap_set_label (const char *device, const char *label);

/* upload.c */
extern int upload_to_fd (int fd, const char *filename);

/* Helper for functions that need a root filesystem mounted. */
#define NEED_ROOT(is_filein,fail_stmt)                                  \
  do {									\
    if (!is_root_mounted ()) {						\
      if (is_filein) cancel_receive ();                                 \
      reply_with_error ("%s: you must call 'mount' first to mount the root filesystem", __func__); \
      fail_stmt;							\
    }									\
  }									\
  while (0)

/* Helper for functions that need an argument ("path") that is absolute. */
#define ABS_PATH(path,is_filein,fail_stmt)                              \
  do {									\
    if ((path)[0] != '/') {						\
      if (is_filein) cancel_receive ();                                 \
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
      const int __old_errno = errno;            \
      if (chroot (sysroot) == -1)               \
        perror ("CHROOT_IN: sysroot");		\
      errno = __old_errno;			\
    }                                           \
  } while (0)
#define CHROOT_OUT				\
  do {						\
    if (sysroot_len > 0) {                      \
      const int __old_errno = errno;            \
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
    const int code = aug_error (aug);                                   \
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

#endif /* GUESTFSD_DAEMON_H */
