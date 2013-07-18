/* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
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

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#endif

#include "hash.h"

#include "guestfs-internal-frontend.h"

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

/* Default, minimum appliance memory size. */
#define DEFAULT_MEMSIZE 500
#define MIN_MEMSIZE 128

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

/* Maximum RPM or dpkg database we will download to /tmp.  RPM
 * 'Packages' database can get very large: 70 MB is roughly the
 * standard size for a new Fedora install, and after lots of package
 * installation/removal I have seen well over 100 MB databases.
 */
#define MAX_PKG_DB_SIZE       (300 * 1000 * 1000)

/* Maximum size of Windows explorer.exe.  2.6MB on Windows 7. */
#define MAX_WINDOWS_EXPLORER_SIZE (4 * 1000 * 1000)

/* Guestfs handle and associated structures. */

/* State. */
enum state { CONFIG = 0, LAUNCHING = 1, READY = 2,
             NO_HANDLE = 0xebadebad };

/* Backend. */
enum backend {
  BACKEND_DIRECT,
  BACKEND_LIBVIRT,
  BACKEND_UNIX,
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

/* Drives added to the handle. */
enum drive_protocol {
  drive_protocol_file,
  drive_protocol_ftp,
  drive_protocol_ftps,
  drive_protocol_gluster,
  drive_protocol_http,
  drive_protocol_https,
  drive_protocol_iscsi,
  drive_protocol_nbd,
  drive_protocol_rbd,
  drive_protocol_sheepdog,
  drive_protocol_ssh,
  drive_protocol_tftp,
};

enum drive_transport {
  drive_transport_none = 0,     /* no transport specified */
  drive_transport_tcp,          /* +tcp */
  drive_transport_unix,         /* +unix */
  /* XXX In theory gluster+rdma could be supported here, but
   * I have no idea what gluster+rdma URLs would look like.
   */
};

struct drive_server {
  enum drive_transport transport;

  /* This field is always non-NULL. */
  union {
    char *hostname;             /* hostname or IP address as a string */
    char *socket;               /* Unix domain socket */
  } u;

  int port;                     /* port number */
};

struct drive_source {
  enum drive_protocol protocol;

  /* This field is always non-NULL.  It may be an empty string. */
  union {
    char *path;                 /* path to file (file) */
    char *exportname;           /* name of export (nbd) */
  } u;

  /* For network transports, zero or more servers can be specified here.
   *
   * - for protocol "nbd": exactly one server
   */
  size_t nr_servers;
  struct drive_server *servers;

  /* Optional username (may be NULL if not specified). */
  char *username;
  /* Optional secret (may be NULL if not specified). */
  char *secret;
};

struct drive {
  struct drive_source src;

  bool readonly;
  char *format;
  char *iface;
  char *name;
  char *disk_label;
  bool use_cache_none;

  /* Data used by the backend. */
  void *priv;
  void (*free_priv) (void *);
};

/* Extra qemu parameters (from guestfs_config). */
struct qemu_param {
  struct qemu_param *next;

  char *qemu_param;
  char *qemu_value;             /* May be NULL. */
};

/* Backend operations. */
struct backend_ops {
  int (*launch) (guestfs_h *g, const char *arg); /* Initialize and launch. */
                                /* Shutdown and cleanup. */
  int (*shutdown) (guestfs_h *g, int check_for_errors);

  int (*get_pid) (guestfs_h *g);         /* get-pid API. */
  int (*max_disks) (guestfs_h *g);       /* max-disks API. */

  /* Hotplugging drives. */
  int (*hot_add_drive) (guestfs_h *g, struct drive *drv, size_t drv_index);
  int (*hot_remove_drive) (guestfs_h *g, struct drive *drv, size_t drv_index);
};
extern struct backend_ops backend_ops_direct;
extern struct backend_ops backend_ops_libvirt;
extern struct backend_ops backend_ops_unix;

/* Connection module.  A 'connection' represents the appliance console
 * connection plus the daemon connection.  It hides the underlying
 * representation (POSIX sockets, virStreamPtr).
 */
struct connection {
  const struct connection_ops *ops;

  /* In the real struct, private data used by each connection module
   * follows here.
   */
};

struct connection_ops {
  /* Close everything and free the connection struct and any internal data. */
  void (*free_connection) (guestfs_h *g, struct connection *);

  /* Accept the connection (back to us) from the daemon.
   *
   * Returns: 1 = accepted, 0 = appliance closed connection, -1 = error
   */
  int (*accept_connection) (guestfs_h *g, struct connection *);

  /* Read/write the given buffer from/to the daemon.  The whole buffer is
   * read or written.  Partial reads/writes are automatically completed
   * if possible, and if this wasn't possible it returns an error.
   *
   * These functions also monitor the console socket and deliver log
   * messages up as events.  This is entirely transparent to the caller.
   *
   * Normal return is number of bytes read/written.  Both functions
   * return 0 to mean that the appliance closed the connection or
   * otherwise went away.  -1 means there's an error.
   */
  ssize_t (*read_data) (guestfs_h *g, struct connection *, void *buf, size_t len);
  ssize_t (*write_data) (guestfs_h *g, struct connection *, const void *buf, size_t len);

  /* Test if data is available to read on the daemon socket, without blocking.
   * Returns: 1 = yes, 0 = no, -1 = error
   */
  int (*can_read_data) (guestfs_h *g, struct connection *);
};

/* Stack of old error handlers. */
struct error_cb_stack {
  struct error_cb_stack   *next;
  guestfs_error_handler_cb error_cb;
  void *                   error_cb_data;
};

/* The libguestfs handle. */
struct guestfs_h
{
  struct guestfs_h *next;	/* Linked list of open handles. */
  enum state state;             /* See the state machine diagram in guestfs(3)*/

  /**** Configuration of the handle. ****/
  bool verbose;                 /* Debugging. */
  bool trace;                   /* Trace calls. */
  bool autosync;                /* Autosync. */
  bool direct_mode;             /* Direct mode. */
  bool recovery_proc;           /* Create a recovery process. */
  bool enable_network;          /* Enable the network. */
  bool selinux;                 /* selinux enabled? */
  bool pgroup;                  /* Create process group for children? */
  bool close_on_exit;           /* Is this handle on the atexit list? */

  int smp;                      /* If > 1, -smp flag passed to qemu. */
  int memsize;			/* Size of RAM (megabytes). */

  char *path;			/* Path to the appliance. */
  char *qemu;			/* Qemu binary. */
  char *append;			/* Append to kernel command line. */

  struct qemu_param *qemu_params; /* Extra qemu parameters. */

  char *program;                /* Program name. */

  /* Array of drives added by add-drive* APIs.
   *
   * Before launch this list can be empty or contain some drives.
   *
   * During launch, a dummy slot may be added which represents the
   * slot taken up by the appliance drive.
   *
   * When hotplugging is supported by the backend, drives can be
   * added to the end of this list after launch.  Also hot-removing a
   * drive causes a NULL slot to appear in the list.
   *
   * During shutdown, this list is deleted, so that each launch gets a
   * fresh set of drives (however callers: don't do this, create a new
   * handle each time).
   *
   * Always use ITER_DRIVES macro to iterate over this list!
   */
  struct drive **drives;
  size_t nr_drives;

#define ITER_DRIVES(g,i,drv)              \
  for (i = 0; i < (g)->nr_drives; ++i)    \
    if (((drv) = (g)->drives[i]) != NULL)

  /* Backend, and associated backend operations. */
  enum backend backend;
  char *backend_arg;
  const struct backend_ops *backend_ops;

  /**** Runtime information. ****/
  char *last_error;             /* Last error on handle. */
  int last_errnum;              /* errno, or 0 if there was no errno */

  /* Temporary and cache directories. */
  /* The actual temporary directory - this is not created with the
   * handle, you have to call guestfs___lazy_make_tmpdir.
   */
  char *tmpdir;
  /* Environment variables that affect tmpdir/cachedir locations. */
  char *env_tmpdir;             /* $TMPDIR (NULL if not set) */
  char *int_tmpdir;   /* $LIBGUESTFS_TMPDIR or guestfs_set_tmpdir or NULL */
  char *int_cachedir; /* $LIBGUESTFS_CACHEDIR or guestfs_set_cachedir or NULL */

  /* Error handler, plus stack of old error handlers. */
  guestfs_error_handler_cb   error_cb;
  void *                     error_cb_data;
  struct error_cb_stack     *error_cb_stack;

  /* Out of memory error handler. */
  guestfs_abort_cb           abort_cb;

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

  /* User cancelled transfer.  Not signal-atomic, but it doesn't
   * matter for this case because we only care if it is != 0.
   */
  int user_cancel;

  struct timeval launch_t;      /* The time that we called guestfs_launch. */

  /* Used by bindtests. */
  FILE *test_fp;

  /* Used to generate unique numbers, eg for temp files.  To use this,
   * '++g->unique'.  Note these are only unique per-handle, not
   * globally unique.
   */
  int unique;

  /* In src/info.c: Use new (JSON) or old (human) qemu-img info parser. */
  int qemu_img_info_parser;
#define QEMU_IMG_INFO_UNKNOWN_PARSER 0
#define QEMU_IMG_INFO_NEW_PARSER 1
#define QEMU_IMG_INFO_OLD_PARSER 2

  /*** Protocol. ***/
  struct connection *conn;              /* Connection to appliance. */
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

#ifdef HAVE_LIBVIRT
  /* Used by src/libvirt-auth.c. */
#define NR_CREDENTIAL_TYPES 9
  unsigned int nr_supported_credentials;
  int supported_credentials[NR_CREDENTIAL_TYPES];
  const char *saved_libvirt_uri; /* Doesn't need to be freed. */
  unsigned int nr_requested_credentials;
  virConnectCredentialPtr requested_credentials;
#endif

  /**** Private data for backends. ****/
  /* NB: This cannot be a union because of a pathological case where
   * the user changes backend while reusing the handle to launch
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

    /* qemu version (0, 0 if unable to parse). */
    int qemu_version_major, qemu_version_minor;

    char **cmdline;   /* Only used in child, does not need freeing. */
    size_t cmdline_size;

    int virtio_scsi;      /* See function qemu_supports_virtio_scsi */
  } direct;

#ifdef HAVE_LIBVIRT
  struct {                      /* Used only by src/launch-libvirt.c. */
    virConnectPtr conn;         /* libvirt connection */
    virDomainPtr dom;           /* libvirt domain */
  } virt;
#endif
  char *virt_selinux_label;
  char *virt_selinux_imagelabel;
  bool virt_selinux_norelabel_disks;
};

/* Per-filesystem data stored for inspect_os. */
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
  OS_TYPE_OPENBSD,
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
  OS_DISTRO_SUSE_BASED,
  OS_DISTRO_SLES,
  OS_DISTRO_OPENBSD,
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
  char *mountable;
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
  char *mountable;
  char *mountpoint;
};

struct guestfs_message_header;
struct guestfs_message_error;
struct guestfs_progress;

/* errors.c */
extern void guestfs___init_error_handler (guestfs_h *g);

extern void guestfs___error_errno (guestfs_h *g, int errnum, const char *fs, ...)
  __attribute__((format (printf,3,4)));
extern void guestfs___perrorf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));

extern void guestfs___warning (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs___debug (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs___trace (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));

extern void guestfs___print_BufferIn (FILE *out, const char *buf, size_t buf_size);
extern void guestfs___print_BufferOut (FILE *out, const char *buf, size_t buf_size);

#define error(g,...) guestfs___error_errno((g),0,__VA_ARGS__)
#define perrorf guestfs___perrorf
#define warning(g,...) guestfs___warning((g),__VA_ARGS__)
#define debug(g,...) \
  do { if ((g)->verbose) guestfs___debug ((g),__VA_ARGS__); } while (0)

#define NOT_SUPPORTED(g,errcode,...)                     \
  do {                                                   \
    guestfs___error_errno ((g), ENOTSUP, __VA_ARGS__);   \
    return (errcode);                                    \
  }                                                      \
  while (0)

extern void guestfs___launch_failed_error (guestfs_h *g);
extern void guestfs___unexpected_close_error (guestfs_h *g);
extern void guestfs___external_command_failed (guestfs_h *g, int status, const char *cmd_name, const char *extra);

/* actions-support.c */
struct trace_buffer {
  FILE *fp;
  char *buf;
  size_t len;
  bool opened;
};

extern int guestfs___check_reply_header (guestfs_h *g, const struct guestfs_message_header *hdr, unsigned int proc_nr, unsigned int serial);
extern int guestfs___check_appliance_up (guestfs_h *g, const char *caller);
extern void guestfs___trace_open (struct trace_buffer *tb);
extern void guestfs___trace_send_line (guestfs_h *g, struct trace_buffer *tb);

/* match.c */
extern int guestfs___match (guestfs_h *g, const char *str, const pcre *re);
extern char *guestfs___match1 (guestfs_h *g, const char *str, const pcre *re);
extern int guestfs___match2 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2);
extern int guestfs___match3 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2, char **ret3);
extern int guestfs___match6 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2, char **ret3, char **ret4, char **ret5, char **ret6);

#define match guestfs___match
#define match1 guestfs___match1
#define match2 guestfs___match2
#define match3 guestfs___match3
#define match6 guestfs___match6

/* proto.c */
extern int guestfs___send (guestfs_h *g, int proc_nr, uint64_t progress_hint, uint64_t optargs_bitmask, xdrproc_t xdrp, char *args);
extern int guestfs___recv (guestfs_h *g, const char *fn, struct guestfs_message_header *hdr, struct guestfs_message_error *err, xdrproc_t xdrp, char *ret);
extern int guestfs___recv_discard (guestfs_h *g, const char *fn);
extern int guestfs___send_file (guestfs_h *g, const char *filename);
extern int guestfs___recv_file (guestfs_h *g, const char *filename);
extern int guestfs___recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn);
extern void guestfs___progress_message_callback (guestfs_h *g, const struct guestfs_progress *message);
extern void guestfs___log_message_callback (guestfs_h *g, const char *buf, size_t len);

/* conn-socket.c */
extern struct connection *guestfs___new_conn_socket_listening (guestfs_h *g, int daemon_accept_sock, int console_sock);
extern struct connection *guestfs___new_conn_socket_connected (guestfs_h *g, int daemon_sock, int console_sock);

/* events.c */
extern void guestfs___call_callbacks_void (guestfs_h *g, uint64_t event);
extern void guestfs___call_callbacks_message (guestfs_h *g, uint64_t event, const char *buf, size_t buf_len);
extern void guestfs___call_callbacks_array (guestfs_h *g, uint64_t event, const uint64_t *array, size_t array_len);

/* tmpdirs.c */
extern int guestfs___set_env_tmpdir (guestfs_h *g, const char *tmpdir);
extern int guestfs___lazy_make_tmpdir (guestfs_h *g);
extern void guestfs___remove_tmpdir (guestfs_h *g);
extern void guestfs___recursive_remove_dir (guestfs_h *g, const char *dir);

/* drives.c */
extern size_t guestfs___checkpoint_drives (guestfs_h *g);
extern void guestfs___rollback_drives (guestfs_h *g, size_t);
extern void guestfs___add_dummy_appliance_drive (guestfs_h *g);
extern void guestfs___free_drives (guestfs_h *g);
extern void guestfs___copy_drive_source (guestfs_h *g, const struct drive_source *src, struct drive_source *dest);
extern char *guestfs___drive_source_qemu_param (guestfs_h *g, const struct drive_source *src);
extern void guestfs___free_drive_source (struct drive_source *src);

/* appliance.c */
extern int guestfs___build_appliance (guestfs_h *g, char **kernel, char **initrd, char **appliance);

/* launch.c */
extern int64_t guestfs___timeval_diff (const struct timeval *x, const struct timeval *y);
extern void guestfs___print_timestamped_message (guestfs_h *g, const char *fs, ...) __attribute__((format (printf,2,3)));
extern void guestfs___launch_send_progress (guestfs_h *g, int perdozen);
extern char *guestfs___appliance_command_line (guestfs_h *g, const char *appliance_dev, int flags);
#define APPLIANCE_COMMAND_LINE_IS_TCG 1

/* launch-appliance.c */
extern char *guestfs___drive_name (size_t index, char *ret);

/* inspect.c */
extern void guestfs___free_inspect_info (guestfs_h *g);
extern char *guestfs___download_to_tmp (guestfs_h *g, struct inspect_fs *fs, const char *filename, const char *basename, uint64_t max_size);
extern struct inspect_fs *guestfs___search_for_root (guestfs_h *g, const char *root);

/* inspect-fs.c */
extern int guestfs___is_file_nocase (guestfs_h *g, const char *);
extern int guestfs___is_dir_nocase (guestfs_h *g, const char *);
extern int guestfs___check_for_filesystem_on (guestfs_h *g,
                                              const char *mountable);
extern int guestfs___parse_unsigned_int (guestfs_h *g, const char *str);
extern int guestfs___parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str);
extern int guestfs___parse_major_minor (guestfs_h *g, struct inspect_fs *fs);
extern char *guestfs___first_line_of_file (guestfs_h *g, const char *filename);
extern int guestfs___first_egrep_of_file (guestfs_h *g, const char *filename, const char *eregex, int iflag, char **ret);
extern void guestfs___check_package_format (guestfs_h *g, struct inspect_fs *fs);
extern void guestfs___check_package_management (guestfs_h *g, struct inspect_fs *fs);

/* inspect-fs-unix.c */
extern int guestfs___check_linux_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_freebsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_netbsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_hurd_root (guestfs_h *g, struct inspect_fs *fs);

/* inspect-fs-windows.c */
extern char *guestfs___case_sensitive_path_silently (guestfs_h *g, const char *);
extern char * guestfs___get_windows_systemroot (guestfs_h *g);
extern int guestfs___check_windows_root (guestfs_h *g, struct inspect_fs *fs, char *windows_systemroot);

/* inspect-fs-cd.c */
extern int guestfs___check_installer_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs___check_installer_iso (guestfs_h *g, struct inspect_fs *fs, const char *device);

/* dbdump.c */
typedef int (*guestfs___db_dump_callback) (guestfs_h *g, const unsigned char *key, size_t keylen, const unsigned char *value, size_t valuelen, void *opaque);
extern int guestfs___read_db_dump (guestfs_h *g, const char *dumpfile, void *opaque, guestfs___db_dump_callback callback);

/* lpj.c */
extern int guestfs___get_lpj (guestfs_h *g);

/* fuse.c */
#if HAVE_FUSE
extern void guestfs___free_fuse (guestfs_h *g);
#endif

/* libvirt-auth.c */
#ifdef HAVE_LIBVIRT
extern virConnectPtr guestfs___open_libvirt_connection (guestfs_h *g, const char *uri, unsigned int flags);
#endif

/* osinfo.c */
struct osinfo {
  /* Data provided by libosinfo database. */
  enum inspect_os_type type;
  enum inspect_os_distro distro;
  char *product_name;
  int major_version;
  int minor_version;
  char *arch;
  int is_live_disk;

#if 0
  /* Not yet available in libosinfo database. */
  char *product_variant;
  int is_netinst_disk;
  int is_multipart_disk;
#endif

  /* The regular expressions used to match ISOs. */
  pcre *re_system_id;
  pcre *re_volume_id;
  pcre *re_publisher_id;
  pcre *re_application_id;
};
extern int guestfs___osinfo_map (guestfs_h *g, const struct guestfs_isoinfo *isoinfo, const struct osinfo **osinfo_ret);

/* command.c */
struct command;
typedef void (*cmd_stdout_callback) (guestfs_h *g, void *data, const char *line, size_t len);
extern struct command *guestfs___new_command (guestfs_h *g);
extern void guestfs___cmd_add_arg (struct command *, const char *arg);
extern void guestfs___cmd_add_arg_format (struct command *, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs___cmd_add_string_unquoted (struct command *, const char *str);
extern void guestfs___cmd_add_string_quoted (struct command *, const char *str);
extern void guestfs___cmd_set_stdout_callback (struct command *, cmd_stdout_callback stdout_callback, void *data, unsigned flags);
#define CMD_STDOUT_FLAG_LINE_BUFFER    0
#define CMD_STDOUT_FLAG_UNBUFFERED      1
#define CMD_STDOUT_FLAG_WHOLE_BUFFER    2
extern void guestfs___cmd_set_stderr_to_stdout (struct command *);
extern void guestfs___cmd_clear_capture_errors (struct command *);
extern void guestfs___cmd_clear_close_files (struct command *);
extern int guestfs___cmd_run (struct command *);
extern void guestfs___cmd_close (struct command *);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_CMD_CLOSE __attribute__((cleanup(guestfs___cleanup_cmd_close)))
#else
#define CLEANUP_CMD_CLOSE
#endif
extern void guestfs___cleanup_cmd_close (void *ptr);

#endif /* GUESTFS_INTERNAL_H_ */
