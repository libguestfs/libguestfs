/* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

#include <stdbool.h>

#include <libintl.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include <pcre.h>

#include "hash.h"

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0
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

#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))

#if ENABLE_PROBES
#include <sys/sdt.h>
/* NB: The 'name' parameter is a literal identifier, NOT a string! */
#define TRACE0(name) DTRACE_PROBE(guestfs, name)
#define TRACE1(name, arg1) \
  DTRACE_PROBE(guestfs, name, (arg1))
#define TRACE2(name, arg1, arg2) \
  DTRACE_PROBE(guestfs, name, (arg1), (arg2))
#define TRACE3(name, arg1, arg2, arg3) \
  DTRACE_PROBE(guestfs, name, (arg1), (arg2), (arg3))
#define TRACE4(name, arg1, arg2, arg3, arg4) \
  DTRACE_PROBE(guestfs, name, (arg1), (arg2), (arg3), (arg4))
#else /* !ENABLE_PROBES */
#define TRACE0(name)
#define TRACE1(name, arg1)
#define TRACE2(name, arg1, arg2)
#define TRACE3(name, arg1, arg2, arg3)
#define TRACE4(name, arg1, arg2, arg3, arg4)
#endif

#define TMP_TEMPLATE_ON_STACK(var)                        \
  const char *ttos_tmpdir = guestfs_tmpdir ();            \
  char var[strlen (ttos_tmpdir) + 32];                    \
  sprintf (var, "%s/libguestfsXXXXXX", ttos_tmpdir)       \

#ifdef __APPLE__
#define UNIX_PATH_MAX 104
#else
#define UNIX_PATH_MAX 108
#endif

#ifndef MAX
#define MAX(a,b) ((a)>(b)?(a):(b))
#endif

#ifdef __APPLE__
#define xdr_uint32_t xdr_u_int32_t
#endif

/* Some limits on what the inspection code will read, for safety. */

/* Small text configuration files.
 *
 * The upper limit is for general files that we grep or download.  The
 * largest such file is probably "txtsetup.sif" from Windows CDs
 * (~500K).  This number has to be larger than any legitimate file and
 * smaller than the protocol message size.
 *
 * The lower limit is for files parsed by Augeas on the daemon side,
 * where Augeas is running in reduced memory and can potentially
 * create a lot of metadata so we really need to be careful about
 * those.
 */
#define MAX_SMALL_FILE_SIZE    (2 * 1000 * 1000)
#define MAX_AUGEAS_FILE_SIZE        (100 * 1000)

/* Maximum Windows Registry hive that we will download to /tmp.  Some
 * registries can be legitimately very large.
 */
#define MAX_REGISTRY_SIZE    (100 * 1000 * 1000)

/* Maximum RPM or dpkg database we will download to /tmp.  RPM
 * 'Packages' database can get very large: 70 MB is roughly the
 * standard size for a new Fedora install, and after lots of package
 * installation/removal I have seen well over 100 MB databases.
 */
#define MAX_PKG_DB_SIZE       (300 * 1000 * 1000)

/* Maximum size of Windows explorer.exe.  2.6MB on Windows 7. */
#define MAX_WINDOWS_EXPLORER_SIZE (4 * 1000 * 1000)

/* GuestFS handle and connection. */
enum state { CONFIG, LAUNCHING, READY, NO_HANDLE };

/* Attach method. */
enum attach_method {
  ATTACH_METHOD_APPLIANCE,
  ATTACH_METHOD_LIBVIRT,
  ATTACH_METHOD_UNIX,
};

/* Event. */
struct event {
  uint64_t event_bitmask;
  guestfs_event_callback cb;
  void *opaque;

  /* opaque2 is not exposed through the API, but is used internally to
   * emulate the old-style callback API.
   */
  void *opaque2;
};

/* Linked list of drives added to the handle. */
struct drive {
  struct drive *next;

  char *path;

  int readonly;
  char *format;
  char *iface;
  char *name;
  bool use_cache_none;
};

/* Extra qemu parameters (from guestfs_config). */
struct qemu_param {
  struct qemu_param *next;

  char *qemu_param;
  char *qemu_value;             /* May be NULL. */
};

/* Backend (attach-method) operations. */
struct attach_ops {
  int (*launch) (guestfs_h *g, const char *arg); /* Initialize and launch. */
  int (*shutdown) (guestfs_h *g); /* Shutdown and cleanup. */

  int (*get_pid) (guestfs_h *g);         /* get-pid API. */
  int (*max_disks) (guestfs_h *g);       /* max-disks API. */
};
extern struct attach_ops attach_ops_appliance;
extern struct attach_ops attach_ops_libvirt;
extern struct attach_ops attach_ops_unix;

struct guestfs_h
{
  struct guestfs_h *next;	/* Linked list of open handles. */
  enum state state;             /* See the state machine diagram in guestfs(3)*/

  /**** Configuration of the handle. ****/
  bool verbose;                 /* Debugging. */
  bool trace;                   /* Trace calls. */
  bool autosync;                /* Autosync. */
  bool direct;                  /* Direct mode. */
  bool recovery_proc;           /* Create a recovery process. */
  bool enable_network;          /* Enable the network. */
  bool selinux;                 /* selinux enabled? */
  bool pgroup;                  /* Create process group for children? */

  int smp;                      /* If > 1, -smp flag passed to qemu. */
  int memsize;			/* Size of RAM (megabytes). */

  char *path;			/* Path to the appliance. */
  char *qemu;			/* Qemu binary. */
  char *append;			/* Append to kernel command line. */

  struct drive *drives;         /* Drives added by add-drive* APIs. */

  struct qemu_param *qemu_params; /* Extra qemu parameters. */

  /* Attach method, and associated backend operations. */
  enum attach_method attach_method;
  char *attach_method_arg;
  const struct attach_ops *attach_ops;

  /**** Runtime information. ****/
  char *tmpdir;			/* Temporary directory containing socket. */

  char *last_error;             /* Last error on handle. */
  int last_errnum;              /* errno, or 0 if there was no errno */

  /* Callbacks. */
  guestfs_abort_cb           abort_cb;
  guestfs_error_handler_cb   error_cb;
  void *                     error_cb_data;

  /* Events. */
  struct event *events;
  size_t nr_events;

  /* Information gathered by inspect_os.  Must be freed by calling
   * guestfs___free_inspect_info.
   */
  struct inspect_fs *fses;
  size_t nr_fses;

  /* Private data area. */
  struct hash_table *pda;
  struct pda_entry *pda_next;

  /* Used by src/actions.c:trace_* functions. */
  FILE *trace_fp;
  char *trace_buf;
  size_t trace_len;

  /* User cancelled transfer.  Not signal-atomic, but it doesn't
   * matter for this case because we only care if it is != 0.
   */
  int user_cancel;

  struct timeval launch_t;      /* The time that we called guestfs_launch. */

  /*** Protocol. ***/
  int fd[2];			/* Stdin/stdout of qemu. */
  int sock;			/* Daemon communications socket. */
  int msg_next_serial;

#if HAVE_FUSE
  /**** Used by the mount-local APIs. ****/
  const char *localmountpoint;
  struct fuse *fuse;                    /* FUSE handle. */
  int ml_dir_cache_timeout;             /* Directory cache timeout. */
  Hash_table *lsc_ht, *xac_ht, *rlc_ht; /* Directory cache. */
  int ml_read_only;                     /* If mounted read-only. */
  int ml_debug_calls;        /* Extra debug info on each FUSE call. */
#endif

  /**** Private data for attach-methods. ****/
  /* NB: This cannot be a union because of a pathological case where
   * the user changes attach-method while reusing the handle to launch
   * multiple times (not a recommended thing to do).  Some fields here
   * cache things across launches so that would break if we used a
   * union.
   */
  struct {                      /* Used only by src/launch-appliance.c. */
    pid_t pid;                  /* Qemu PID. */
    pid_t recoverypid;          /* Recovery process PID. */

    char *qemu_help;            /* Output of qemu -help. */
    char *qemu_version;         /* Output of qemu -version. */
    char *qemu_devices;         /* Output of qemu -device ? */

    char **cmdline;   /* Only used in child, does not need freeing. */
    size_t cmdline_size;

    bool virtio_scsi;     /* See function qemu_supports_virtio_scsi */
  } app;

  struct {                      /* Used only by src/launch-libvirt.c. */
    void *connv;                /* libvirt connection (really virConnectPtr) */
    void *domv;                 /* libvirt domain (really virDomainPtr) */
  } virt;
};

/* Per-filesystem data stored for inspect_os. */
enum inspect_fs_content {
  FS_CONTENT_UNKNOWN = 0,
  FS_CONTENT_LINUX_ROOT,
  FS_CONTENT_WINDOWS_ROOT,
  FS_CONTENT_WINDOWS_VOLUME_WITH_APPS,
  FS_CONTENT_WINDOWS_VOLUME,
  FS_CONTENT_LINUX_BOOT,
  FS_CONTENT_LINUX_USR,
  FS_CONTENT_LINUX_USR_LOCAL,
  FS_CONTENT_LINUX_VAR,
  FS_CONTENT_FREEBSD_ROOT,
  FS_CONTENT_NETBSD_ROOT,
  FS_CONTENT_INSTALLER,
  FS_CONTENT_HURD_ROOT,
  FS_CONTENT_FREEDOS_ROOT,
};

enum inspect_os_format {
  OS_FORMAT_UNKNOWN = 0,
  OS_FORMAT_INSTALLED,
  OS_FORMAT_INSTALLER,
  /* in future: supplemental disks */
};

enum inspect_os_type {
  OS_TYPE_UNKNOWN = 0,
  OS_TYPE_LINUX,
  OS_TYPE_WINDOWS,
  OS_TYPE_FREEBSD,
  OS_TYPE_NETBSD,
  OS_TYPE_HURD,
  OS_TYPE_DOS,
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
  OS_DISTRO_LINUX_MINT,
  OS_DISTRO_MANDRIVA,
  OS_DISTRO_SLACKWARE,
  OS_DISTRO_CENTOS,
  OS_DISTRO_SCIENTIFIC_LINUX,
  OS_DISTRO_TTYLINUX,
  OS_DISTRO_MAGEIA,
  OS_DISTRO_OPENSUSE,
  OS_DISTRO_BUILDROOT,
  OS_DISTRO_CIRROS,
  OS_DISTRO_FREEDOS,
};

enum inspect_os_package_format {
  OS_PACKAGE_FORMAT_UNKNOWN = 0,
  OS_PACKAGE_FORMAT_RPM,
  OS_PACKAGE_FORMAT_DEB,
  OS_PACKAGE_FORMAT_PACMAN,
  OS_PACKAGE_FORMAT_EBUILD,
  OS_PACKAGE_FORMAT_PISI,
  OS_PACKAGE_FORMAT_PKGSRC,
};

enum inspect_os_package_management {
  OS_PACKAGE_MANAGEMENT_UNKNOWN = 0,
  OS_PACKAGE_MANAGEMENT_YUM,
  OS_PACKAGE_MANAGEMENT_UP2DATE,
  OS_PACKAGE_MANAGEMENT_APT,
  OS_PACKAGE_MANAGEMENT_PACMAN,
  OS_PACKAGE_MANAGEMENT_PORTAGE,
  OS_PACKAGE_MANAGEMENT_PISI,
  OS_PACKAGE_MANAGEMENT_URPMI,
  OS_PACKAGE_MANAGEMENT_ZYPPER,
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
  char *product_variant;
  int major_version;
  int minor_version;
  char *arch;
  char *hostname;
  char *windows_systemroot;
  char *windows_current_control_set;
  char **drive_mappings;
  enum inspect_os_format format;
  int is_live_disk;
  int is_netinst_disk;
  int is_multipart_disk;
  struct inspect_fstab_entry *fstab;
  size_t nr_fstab;
};

struct inspect_fstab_entry {
  char *device;
  char *mountpoint;
};

struct guestfs_message_header;
struct guestfs_message_error;
struct guestfs_progress;

extern void guestfs_error (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_error_errno (guestfs_h *g, int errnum, const char *fs, ...)
  __attribute__((format (printf,3,4)));
extern void guestfs_perrorf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void *guestfs_safe_realloc (guestfs_h *g, void *ptr, size_t nbytes);
extern char *guestfs_safe_strdup (guestfs_h *g, const char *str);
extern char *guestfs_safe_strndup (guestfs_h *g, const char *str, size_t n);
extern void *guestfs_safe_memdup (guestfs_h *g, void *ptr, size_t size);
extern char *guestfs_safe_asprintf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs___warning (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs___debug (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs___trace (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern const char *guestfs___persistent_tmpdir (void);
extern void guestfs___remove_tmpdir (const char *dir);
extern int64_t guestfs___timeval_diff (const struct timeval *x, const struct timeval *y);
extern void guestfs___print_timestamped_message (guestfs_h *g, const char *fs, ...);
#if HAVE_FUSE
extern void guestfs___free_fuse (guestfs_h *g);
#endif
extern void guestfs___free_inspect_info (guestfs_h *g);
extern void guestfs___free_drives (struct drive **drives);
extern int guestfs___send (guestfs_h *g, int proc_nr, uint64_t progress_hint, uint64_t optargs_bitmask, xdrproc_t xdrp, char *args);
extern int guestfs___recv (guestfs_h *g, const char *fn, struct guestfs_message_header *hdr, struct guestfs_message_error *err, xdrproc_t xdrp, char *ret);
extern int guestfs___recv_discard (guestfs_h *g, const char *fn);
extern int guestfs___send_file (guestfs_h *g, const char *filename);
extern int guestfs___recv_file (guestfs_h *g, const char *filename);
extern int guestfs___send_to_daemon (guestfs_h *g, const void *v_buf, size_t n);
extern int guestfs___recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn);
extern int guestfs___accept_from_daemon (guestfs_h *g);
extern void guestfs___progress_message_callback (guestfs_h *g, const struct guestfs_progress *message);
extern int guestfs___build_appliance (guestfs_h *g, char **kernel, char **initrd, char **appliance);
extern int guestfs___launch_appliance (guestfs_h *g);
extern int guestfs___launch_unix (guestfs_h *g, const char *sockpath);
extern void guestfs___launch_send_progress (guestfs_h *g, int perdozen);
extern void guestfs___print_BufferIn (FILE *out, const char *buf, size_t buf_size);
extern void guestfs___print_BufferOut (FILE *out, const char *buf, size_t buf_size);
extern int guestfs___match (guestfs_h *g, const char *str, const pcre *re);
extern char *guestfs___match1 (guestfs_h *g, const char *str, const pcre *re);
extern int guestfs___match2 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2);
extern int guestfs___match3 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2, char **ret3);
extern int guestfs___feature_available (guestfs_h *g, const char *feature);
extern void guestfs___free_string_list (char **);
extern struct drive ** guestfs___checkpoint_drives (guestfs_h *g);
extern void guestfs___rollback_drives (guestfs_h *g, struct drive **i);
extern void guestfs___call_callbacks_void (guestfs_h *g, uint64_t event);
extern void guestfs___call_callbacks_message (guestfs_h *g, uint64_t event, const char *buf, size_t buf_len);
extern void guestfs___call_callbacks_array (guestfs_h *g, uint64_t event, const uint64_t *array, size_t array_len);
extern int guestfs___is_file_nocase (guestfs_h *g, const char *);
extern int guestfs___is_dir_nocase (guestfs_h *g, const char *);
extern char *guestfs___download_to_tmp (guestfs_h *g, struct inspect_fs *fs, const char *filename, const char *basename, uint64_t max_size);
extern char *guestfs___case_sensitive_path_silently (guestfs_h *g, const char *);
extern struct inspect_fs *guestfs___search_for_root (guestfs_h *g, const char *root);
extern char *guestfs___drive_name (size_t index, char *ret);

#if defined(HAVE_HIVEX)
extern int guestfs___check_for_filesystem_on (guestfs_h *g, const char *device, int is_block, int is_partnum);
extern int guestfs___parse_unsigned_int (guestfs_h *g, const char *str);
extern int guestfs___parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str);
extern int guestfs___parse_major_minor (guestfs_h *g, struct inspect_fs *fs);
extern char *guestfs___first_line_of_file (guestfs_h *g, const char *filename);
extern int guestfs___first_egrep_of_file (guestfs_h *g, const char *filename, const char *eregex, int iflag, char **ret);
typedef int (*guestfs___db_dump_callback) (guestfs_h *g, const unsigned char *key, size_t keylen, const unsigned char *value, size_t valuelen, void *opaque);
extern int guestfs___read_db_dump (guestfs_h *g, const char *dumpfile, void *opaque, guestfs___db_dump_callback callback);
extern int guestfs___check_installer_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_linux_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_freebsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_netbsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_hurd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___has_windows_systemroot (guestfs_h *g);
extern int guestfs___check_windows_root (guestfs_h *g, struct inspect_fs *fs);
#endif

#define error(g,...) guestfs_error_errno((g),0,__VA_ARGS__)
#define perrorf guestfs_perrorf
#define warning(g,...) guestfs___warning((g),__VA_ARGS__)
#define debug(g,...) \
  do { if ((g)->verbose) guestfs___debug ((g),__VA_ARGS__); } while (0)
#define safe_calloc guestfs_safe_calloc
#define safe_malloc guestfs_safe_malloc
#define safe_realloc guestfs_safe_realloc
#define safe_strdup guestfs_safe_strdup
#define safe_strndup guestfs_safe_strndup
#define safe_memdup guestfs_safe_memdup
#define safe_asprintf guestfs_safe_asprintf
#define match guestfs___match
#define match1 guestfs___match1
#define match2 guestfs___match2
#define match3 guestfs___match3

#endif /* GUESTFS_INTERNAL_H_ */
