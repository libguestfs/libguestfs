/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2011 Red Hat Inc.
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

/*-- in guestfsd.c --*/
extern int verbose;

extern int autosync_umount;

extern const char *sysroot;
extern size_t sysroot_len;

extern char *sysroot_path (const char *path);

extern int is_root_device (const char *device);

extern int xwrite (int sock, const void *buf, size_t len)
  __attribute__((__warn_unused_result__));
extern int xread (int sock, void *buf, size_t len)
  __attribute__((__warn_unused_result__));

extern int add_string (char ***argv, int *size, int *alloc, const char *str);
extern size_t count_strings (char *const *argv);
extern void sort_strings (char **argv, int len);
extern void free_strings (char **argv);
extern void free_stringslen (char **argv, int len);

extern int is_power_of_2 (unsigned long v);

#define command(out,err,name,...) commandf((out),(err),0,(name),__VA_ARGS__)
#define commandr(out,err,name,...) commandrf((out),(err),0,(name),__VA_ARGS__)
#define commandv(out,err,argv) commandvf((out),(err),0,(argv))
#define commandrv(out,err,argv) commandrvf((out),(err),0,(argv))

#define COMMAND_FLAG_FD_MASK                   (1024-1)
#define COMMAND_FLAG_FOLD_STDOUT_ON_STDERR     1024
#define COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN 2048

extern int commandf (char **stdoutput, char **stderror, int flags,
                     const char *name, ...);
extern int commandrf (char **stdoutput, char **stderror, int flags,
                      const char *name, ...);
extern int commandvf (char **stdoutput, char **stderror, int flags,
                      char const *const *argv);
extern int commandrvf (char **stdoutput, char **stderror, int flags,
                       char const* const *argv);

extern char **split_lines (char *str);

extern void trim (char *str);

extern int device_name_translation (char *device);

extern int prog_exists (const char *prog);

extern void udev_settle (void);

/* This just stops gcc from giving a warning about our custom printf
 * formatters %Q and %R.  See guestfs(3)/EXTENDING LIBGUESTFS for more
 * info about these.
 */
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

/*-- in names.c (auto-generated) --*/
extern const char *function_names[];

/*-- in proto.c --*/
extern int proc_nr;
extern int serial;
extern uint64_t progress_hint;
extern uint64_t optargs_bitmask;

/*-- in mount.c --*/
extern int is_root_mounted (void);

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

/*-- in sync.c --*/
/* Use this as a replacement for sync(2). */
extern int sync_disks (void);

/*-- in ext2.c --*/
extern int e2prog (char *name); /* Massive hack for RHEL 5. */

/*-- in lvm.c --*/
extern int lv_canonical (const char *device, char **ret);

/*-- in lvm-filter.c --*/
extern void copy_lvm (void);

/*-- in proto.c --*/
extern void main_loop (int sock) __attribute__((noreturn));

/* ordinary daemon functions use these to indicate errors
 * NB: you don't need to prefix the string with the current command,
 * it is added automatically by the client-side RPC stubs.
 */
extern void reply_with_error (const char *fs, ...)
  __attribute__((format (printf,1,2)));
extern void reply_with_perror_errno (int err, const char *fs, ...)
  __attribute__((format (printf,2,3)));
#define reply_with_perror(...) reply_with_perror_errno(errno, __VA_ARGS__)

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
extern int send_file_write (const void *buf, int len);
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

/* All functions that need an argument that is a device or partition name
 * must call this macro.  It checks that the device exists and does
 * device name translation (described in the guestfs(3) manpage).
 * Note that the "path" argument may be modified.
 *
 * NB. Cannot be used for FileIn functions.
 */
#define RESOLVE_DEVICE(path,cancel_stmt,fail_stmt)                      \
  do {									\
    if (STRNEQLEN ((path), "/dev/", 5)) {				\
      cancel_stmt;                                                      \
      reply_with_error ("%s: %s: expecting a device name", __func__, (path)); \
      fail_stmt;							\
    }									\
    if (is_root_device (path))                                          \
      reply_with_error ("%s: %s: device not found", __func__, path);    \
    if (device_name_translation ((path)) == -1) {                       \
      int err = errno;                                                  \
      cancel_stmt;                                                      \
      errno = err;                                                      \
      reply_with_perror ("%s: %s", __func__, path);                     \
      fail_stmt;							\
    }                                                                   \
  } while (0)

/* Helper for functions which need either an absolute path in the
 * mounted filesystem, OR a /dev/ device which exists.
 *
 * NB. Cannot be used for FileIn functions.
 *
 * NB #2: Functions which mix filenames and device paths should be
 * avoided, and existing functions should be deprecated.  This is
 * because we intend in future to make device parameters a distinct
 * type from filenames.
 */
#define REQUIRE_ROOT_OR_RESOLVE_DEVICE(path,cancel_stmt,fail_stmt)      \
  do {									\
    if (STREQLEN ((path), "/dev/", 5))                                  \
      RESOLVE_DEVICE ((path), cancel_stmt, fail_stmt);                  \
    else {								\
      NEED_ROOT (cancel_stmt, fail_stmt);                               \
      ABS_PATH ((path), cancel_stmt, fail_stmt);                        \
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

/* Marks functions which are not available.
 * NB. Cannot be used for FileIn functions.
 */
#define NOT_AVAILABLE(errcode)                                          \
  do {									\
    reply_with_error ("%s: function not available", __func__);          \
    return (errcode);							\
  }									\
  while (0)

#ifndef __attribute__
# if __GNUC__ < 2 || (__GNUC__ == 2 && __GNUC_MINOR__ < 8)
#  define __attribute__(x) /* empty */
# endif
#endif

#ifndef ATTRIBUTE_UNUSED
# define ATTRIBUTE_UNUSED __attribute__ ((__unused__))
#endif

#define STREQ(a,b) (strcmp((a),(b)) == 0)
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)

#endif /* GUESTFSD_DAEMON_H */
