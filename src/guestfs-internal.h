/* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

#ifndef GUESTFS_INTERNAL_H_
#define GUESTFS_INTERNAL_H_

#include <rpc/types.h>
#include <rpc/xdr.h>

#ifdef HAVE_PCRE
#include <pcre.h>
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

#ifdef HAVE_GETTEXT
#include "gettext.h"
#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))
#else
#define _(str) str
#define N_(str) str
#endif

#define TMP_TEMPLATE_ON_STACK(var)                        \
  const char *ttos_tmpdir = guestfs_tmpdir ();            \
  char var[strlen (ttos_tmpdir) + 32];                    \
  sprintf (var, "%s/libguestfsXXXXXX", ttos_tmpdir)       \

#define UNIX_PATH_MAX 108

#ifndef MAX
#define MAX(a,b) ((a)>(b)?(a):(b))
#endif

#ifdef __APPLE__
#define xdr_uint32_t xdr_u_int32_t
#endif

/* Network configuration of the appliance.  Note these addresses are
 * only meaningful within the context of the running appliance.  QEMU
 * translates network connections to these magic addresses into
 * userspace calls on the host (eg. connect(2)).  qemu-doc has a nice
 * diagram which is also useful to refer to.
 *
 * NETWORK: The network.
 *
 * ROUTER: The address of the "host", ie. this library.
 *
 * [Note: If you change NETWORK and ROUTER then you also have to
 * change the network configuration in appliance/init].
 *
 * GUESTFWD_ADDR, GUESTFWD_PORT: The guestfwd feature of qemu
 * magically connects this pseudo-address to the guestfwd channel.  In
 * typical Linux configurations of libguestfs, guestfwd is not
 * actually used any more.
 */
#define NETWORK "169.254.0.0/16"
#define ROUTER "169.254.2.2"

/* GuestFS handle and connection. */
enum state { CONFIG, LAUNCHING, READY, BUSY, NO_HANDLE };

struct guestfs_h
{
  struct guestfs_h *next;	/* Linked list of open handles. */

  /* State: see the state machine diagram in the man page guestfs(3). */
  enum state state;

  int fd[2];			/* Stdin/stdout of qemu. */
  int sock;			/* Daemon communications socket. */
  pid_t pid;			/* Qemu PID. */
  pid_t recoverypid;		/* Recovery process PID. */

  struct timeval launch_t;      /* The time that we called guestfs_launch. */

  char *tmpdir;			/* Temporary directory containing socket. */

  char *qemu_help, *qemu_version; /* Output of qemu -help, qemu -version. */

  char **cmdline;		/* Qemu command line. */
  int cmdline_size;

  int verbose;
  int trace;
  int autosync;
  int direct;
  int recovery_proc;
  int enable_network;

  char *path;			/* Path to kernel, initrd. */
  char *qemu;			/* Qemu binary. */
  char *append;			/* Append to kernel command line. */

  int memsize;			/* Size of RAM (megabytes). */

  int selinux;                  /* selinux enabled? */

  char *last_error;
  int last_errnum;              /* errno, or 0 if there was no errno */

  /* Callbacks. */
  guestfs_abort_cb           abort_cb;
  guestfs_error_handler_cb   error_cb;
  void *                     error_cb_data;
  guestfs_log_message_cb     log_message_cb;
  void *                     log_message_cb_data;
  guestfs_subprocess_quit_cb subprocess_quit_cb;
  void *                     subprocess_quit_cb_data;
  guestfs_launch_done_cb     launch_done_cb;
  void *                     launch_done_cb_data;
  guestfs_close_cb           close_cb;
  void *                     close_cb_data;
  guestfs_progress_cb        progress_cb;
  void *                     progress_cb_data;

  int msg_next_serial;

  /* Information gathered by inspect_os.  Must be freed by calling
   * guestfs___free_inspect_info.
   */
  struct inspect_fs *fses;
  size_t nr_fses;

  /* Private data area. */
  struct hash_table *pda;
};

/* Per-filesystem data stored for inspect_os. */
enum inspect_fs_content {
  FS_CONTENT_UNKNOWN = 0,
  FS_CONTENT_LINUX_ROOT,
  FS_CONTENT_WINDOWS_ROOT,
  FS_CONTENT_LINUX_BOOT,
  FS_CONTENT_LINUX_USR,
  FS_CONTENT_LINUX_USR_LOCAL,
  FS_CONTENT_LINUX_VAR,
};

enum inspect_os_type {
  OS_TYPE_UNKNOWN = 0,
  OS_TYPE_LINUX,
  OS_TYPE_WINDOWS,
};

enum inspect_os_distro {
  OS_DISTRO_UNKNOWN = 0,
  OS_DISTRO_DEBIAN,
  OS_DISTRO_FEDORA,
  OS_DISTRO_REDHAT_BASED,
  OS_DISTRO_RHEL,
  OS_DISTRO_WINDOWS,
  OS_DISTRO_PARDUS,
  OS_DISTRO_ARCHLINUX,
  OS_DISTRO_GENTOO,
  OS_DISTRO_UBUNTU,
  OS_DISTRO_MEEGO,
};

enum inspect_os_package_format {
  OS_PACKAGE_FORMAT_UNKNOWN = 0,
  OS_PACKAGE_FORMAT_RPM,
  OS_PACKAGE_FORMAT_DEB,
  OS_PACKAGE_FORMAT_PACMAN,
  OS_PACKAGE_FORMAT_EBUILD,
  OS_PACKAGE_FORMAT_PISI
};

enum inspect_os_package_management {
  OS_PACKAGE_MANAGEMENT_UNKNOWN = 0,
  OS_PACKAGE_MANAGEMENT_YUM,
  OS_PACKAGE_MANAGEMENT_UP2DATE,
  OS_PACKAGE_MANAGEMENT_APT,
  OS_PACKAGE_MANAGEMENT_PACMAN,
  OS_PACKAGE_MANAGEMENT_PORTAGE,
  OS_PACKAGE_MANAGEMENT_PISI,
};

struct inspect_fs {
  int is_root;
  char *device;
  int is_mountable;
  int is_swap;
  enum inspect_fs_content content;
  enum inspect_os_type type;
  enum inspect_os_distro distro;
  enum inspect_os_package_format package_format;
  enum inspect_os_package_management package_management;
  char *product_name;
  int major_version;
  int minor_version;
  char *arch;
  char *windows_systemroot;
  struct inspect_fstab_entry *fstab;
  size_t nr_fstab;
};

struct inspect_fstab_entry {
  char *device;
  char *mountpoint;
};

struct guestfs_message_header;
struct guestfs_message_error;

extern void guestfs_error (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_error_errno (guestfs_h *g, int errnum, const char *fs, ...)
  __attribute__((format (printf,3,4)));
extern void guestfs_perrorf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void *guestfs_safe_realloc (guestfs_h *g, void *ptr, int nbytes);
extern char *guestfs_safe_strdup (guestfs_h *g, const char *str);
extern char *guestfs_safe_strndup (guestfs_h *g, const char *str, size_t n);
extern void *guestfs_safe_memdup (guestfs_h *g, void *ptr, size_t size);
extern void guestfs___print_timestamped_argv (guestfs_h *g, const char *argv[]);
extern void guestfs___print_timestamped_message (guestfs_h *g, const char *fs, ...);
extern void guestfs___free_inspect_info (guestfs_h *g);
extern int guestfs___set_busy (guestfs_h *g);
extern int guestfs___end_busy (guestfs_h *g);
extern int guestfs___send (guestfs_h *g, int proc_nr, xdrproc_t xdrp, char *args);
extern int guestfs___recv (guestfs_h *g, const char *fn, struct guestfs_message_header *hdr, struct guestfs_message_error *err, xdrproc_t xdrp, char *ret);
extern int guestfs___send_file (guestfs_h *g, const char *filename);
extern int guestfs___recv_file (guestfs_h *g, const char *filename);
extern int guestfs___send_to_daemon (guestfs_h *g, const void *v_buf, size_t n);
extern int guestfs___recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn);
extern int guestfs___accept_from_daemon (guestfs_h *g);
extern int guestfs___build_appliance (guestfs_h *g, char **kernel, char **initrd, char **appliance);
extern void guestfs___print_BufferIn (FILE *out, const char *buf, size_t buf_size);
#ifdef HAVE_PCRE
extern int guestfs___match (guestfs_h *g, const char *str, const pcre *re);
extern char *guestfs___match1 (guestfs_h *g, const char *str, const pcre *re);
extern int guestfs___match2 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2);
#endif
extern int guestfs___feature_available (guestfs_h *g, const char *feature);
extern void guestfs___free_string_list (char **);
extern int guestfs___checkpoint_cmdline (guestfs_h *g);
extern void guestfs___rollback_cmdline (guestfs_h *g, int pos);

#define error(g,...) guestfs_error_errno((g),0,__VA_ARGS__)
#define perrorf guestfs_perrorf
#define safe_calloc guestfs_safe_calloc
#define safe_malloc guestfs_safe_malloc
#define safe_realloc guestfs_safe_realloc
#define safe_strdup guestfs_safe_strdup
#define safe_strndup guestfs_safe_strndup
#define safe_memdup guestfs_safe_memdup
#ifdef HAVE_PCRE
#define match guestfs___match
#define match1 guestfs___match1
#define match2 guestfs___match2
#endif

#endif /* GUESTFS_INTERNAL_H_ */
