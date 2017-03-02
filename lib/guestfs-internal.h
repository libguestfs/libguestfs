/* libguestfs
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * This header file is included in the libguestfs library (F<lib/>)
 * only.
 *
 * See also F<lib/guestfs-internal-frontend.h> and
 * F<lib/guestfs-internal-all.h>
 */

#ifndef GUESTFS_INTERNAL_H_
#define GUESTFS_INTERNAL_H_

#include <stdbool.h>

#include <rpc/types.h>  /* Needed on libc's different than glibc. */
#include <rpc/xdr.h>

#include <pcre.h>

/* Minimum required version of libvirt for the libvirt backend.
 *
 * This is also checked at runtime because you can dynamically link
 * with a different version from what you were compiled with.
 */
#define MIN_LIBVIRT_MAJOR 0
#define MIN_LIBVIRT_MINOR 10
#define MIN_LIBVIRT_MICRO 2 /* XXX patches in > 2 already */
#define MIN_LIBVIRT_VERSION (MIN_LIBVIRT_MAJOR * 1000000 +	\
                             MIN_LIBVIRT_MINOR * 1000 +		\
                             MIN_LIBVIRT_MICRO)

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#if LIBVIR_VERSION_NUMBER >= MIN_LIBVIRT_VERSION
#define HAVE_LIBVIRT_BACKEND
#endif
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

/* Default and minimum appliance memory size. */

/* Needs to be larger on ppc64 because of the larger page size (64K).
 * For example, test-max-disks won't pass unless we increase the
 * default memory size since the system runs out of memory when
 * creating device nodes.
 */
#ifdef __powerpc__
#  define DEFAULT_MEMSIZE 768
#  define MIN_MEMSIZE 256
#endif

/* Kernel 3.19 is unable to uncompress the initramfs on aarch64 unless
 * we have > 500 MB of space.  This looks like a kernel bug (earlier
 * kernels have no problems).  However since 64 KB pages are also
 * common on aarch64, treat this like the ppc case above.
 */
#ifdef __aarch64__
#  define DEFAULT_MEMSIZE 768
#  define MIN_MEMSIZE 256
#endif

/* The default and minimum memory size for most users. */
#ifndef DEFAULT_MEMSIZE
#  define DEFAULT_MEMSIZE 500
#endif
#ifndef MIN_MEMSIZE
#  define MIN_MEMSIZE 128
#endif

/* Timeout waiting for appliance to come up (seconds).
 *
 * XXX This is just a large timeout for now.  Should make this
 * configurable.  Also it interacts with libguestfs-test-tool -t
 * option.
 */
#define APPLIANCE_TIMEOUT (20*60) /* 20 mins */

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

/* Differences in device names on ARM (virtio-mmio) vs normal
 * hardware with PCI.
 */
#if !defined(__arm__)
#define VIRTIO_BLK "virtio-blk-pci"
#define VIRTIO_SCSI "virtio-scsi-pci"
#define VIRTIO_SERIAL "virtio-serial-pci"
#define VIRTIO_NET "virtio-net-pci"
#else /* ARMv7 */
#define VIRTIO_BLK "virtio-blk-device"
#define VIRTIO_SCSI "virtio-scsi-device"
#define VIRTIO_SERIAL "virtio-serial-device"
#define VIRTIO_NET "virtio-net-device"
#endif /* ARMv7 */

/* Machine types. */
#ifdef __arm__
#define MACHINE_TYPE "virt"
#endif
#ifdef __aarch64__
#define MACHINE_TYPE "virt"
#endif
#ifdef __powerpc__
#define MACHINE_TYPE "pseries"
#endif

/* Guestfs handle and associated structures. */

/* State. */
enum state { CONFIG = 0, LAUNCHING = 1, READY = 2,
             NO_HANDLE = 0xebadebad };

/**
 * This struct is used to maintain a list of events registered
 * against the handle.  See C<g-E<gt>events> in the handle.
 */
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

  /* Format (eg. raw, qcow2).  NULL = autodetect. */
  char *format;

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

enum discard {
  discard_disable = 0,
  discard_enable,
  discard_besteffort,
};

/**
 * There is one C<struct drive> per drive, including hot-plugged drives.
 */
struct drive {
  /* Original source of the drive, eg. file:..., http:... */
  struct drive_source src;

  /* If the drive is readonly, then an overlay [a local file] is
   * created before launch to protect the original drive content, and
   * the filename is stored here.  Backends should open this file if
   * it is non-NULL, else consult the original source above.
   *
   * Note that the overlay is in a backend-specific format, probably
   * different from the source format.  eg. qcow2, UML COW.
   */
  char *overlay;

  /* Various per-drive flags. */
  bool readonly;
  char *iface;
  char *name;
  char *disk_label;
  char *cachemode;
  enum discard discard;
  bool copyonread;
};

/* Extra hv parameters (from guestfs_config). */
struct hv_param {
  struct hv_param *next;

  char *hv_param;
  char *hv_value;               /* May be NULL. */
};

/**
 * Backend operations.
 *
 * Each backend (eg. libvirt, direct) defines some functions which get
 * run at various places in the handle lifecycle (eg. at launch,
 * shutdown).  The backend defines this struct pointing to those
 * functions.
 */
struct backend_ops {
  /* Size (in bytes) of the per-handle data structure needed by this
   * backend.  The data pointer is allocated and freed by libguestfs
   * and passed to the functions in the 'void *data' parameter.
   * Inside the data structure is opaque to libguestfs.  Any strings
   * etc pointed to by it must be freed by the backend during
   * shutdown.
   */
  size_t data_size;

  /* Create a COW overlay on top of a drive.  This must be a local
   * file, created in the temporary directory.  This is called when
   * the drive is added to the handle.
   */
  char *(*create_cow_overlay) (guestfs_h *g, void *data, struct drive *drv);

  /* Launch and shut down. */
  int (*launch) (guestfs_h *g, void *data, const char *arg);
  int (*shutdown) (guestfs_h *g, void *data, int check_for_errors);

  /* Miscellaneous. */
  int (*get_pid) (guestfs_h *g, void *data);
  int (*max_disks) (guestfs_h *g, void *data);

  /* Hotplugging drives. */
  int (*hot_add_drive) (guestfs_h *g, void *data, struct drive *drv, size_t drv_index);
  int (*hot_remove_drive) (guestfs_h *g, void *data, struct drive *drv, size_t drv_index);
};

/**
 * Connection module.
 *
 * A C<connection> represents the appliance console connection plus
 * the daemon connection.  It hides the underlying representation
 * (POSIX sockets, C<virStreamPtr>).
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
   * There is an implicit timeout (APPLIANCE_TIMEOUT defined above).
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

  /* Get the console socket (to support virt-rescue). */
  int (*get_console_sock) (guestfs_h *g, struct connection *);
};

/**
 * Stack of old error handlers.
 */
struct error_cb_stack {
  struct error_cb_stack   *next;
  guestfs_error_handler_cb error_cb;
  void *                   error_cb_data;
};

/**
 * Cache of queried features.
 *
 * Used to cache the appliance features (see F<lib/available.c>).
 */
struct cached_feature {
  char *group;
  int result;
};

/**
 * The libguestfs handle.
 */
struct guestfs_h {
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

  int smp;                      /* If > 1, -smp flag passed to hv. */
  int memsize;			/* Size of RAM (megabytes). */

  char *path;			/* Path to the appliance. */
  char *hv;			/* Hypervisor (HV) binary. */
  char *append;			/* Append to kernel command line. */

  struct hv_param *hv_params;   /* Extra hv parameters. */

  char *program;                /* Program name. */
  char *identifier;             /* Handle identifier. */

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

  /* Backend.  NB: Use guestfs_int_set_backend to change the backend. */
  char *backend;                /* The full string, always non-NULL. */
  char *backend_arg;            /* Pointer to the argument part. */
  const struct backend_ops *backend_ops;
  void *backend_data;           /* Per-handle data. */
  char **backend_settings;      /* Backend settings (can be NULL). */

  /**** Runtime information. ****/
  char *last_error;             /* Last error on handle. */
  int last_errnum;              /* errno, or 0 if there was no errno */

  /* Temporary and cache directories. */
  /* The actual temporary directory - this is not created with the
   * handle, you have to call guestfs_int_lazy_make_tmpdir.
   */
  char *tmpdir;
  char *sockdir;
  /* Environment variables that affect tmpdir/cachedir/sockdir locations. */
  char *env_tmpdir;             /* $TMPDIR (NULL if not set) */
  char *env_runtimedir;         /* $XDG_RUNTIME_DIR (NULL if not set)*/
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
   * guestfs_int_free_inspect_info.
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

#ifdef HAVE_LIBVIRT_BACKEND
  /* Used by lib/libvirt-auth.c. */
#define NR_CREDENTIAL_TYPES 9
  unsigned int nr_supported_credentials;
  int supported_credentials[NR_CREDENTIAL_TYPES];
  const char *saved_libvirt_uri; /* Doesn't need to be freed. */
  bool wrapper_warning_done;
  unsigned int nr_requested_credentials;
  virConnectCredentialPtr requested_credentials;
#endif

  /* Cached features. */
  struct cached_feature *features;
  size_t nr_features;
};

/**
 * Used for storing major.minor.micro version numbers.
 * See F<lib/version.c> for more information.
 */
struct version {
  int v_major;
  int v_minor;
  int v_micro;
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
  OS_TYPE_MINIX,
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
  OS_DISTRO_ORACLE_LINUX,
  OS_DISTRO_FREEBSD,
  OS_DISTRO_NETBSD,
  OS_DISTRO_COREOS,
  OS_DISTRO_ALPINE_LINUX,
  OS_DISTRO_ALTLINUX,
  OS_DISTRO_FRUGALWARE,
  OS_DISTRO_PLD_LINUX,
  OS_DISTRO_VOID_LINUX,
};

enum inspect_os_package_format {
  OS_PACKAGE_FORMAT_UNKNOWN = 0,
  OS_PACKAGE_FORMAT_RPM,
  OS_PACKAGE_FORMAT_DEB,
  OS_PACKAGE_FORMAT_PACMAN,
  OS_PACKAGE_FORMAT_EBUILD,
  OS_PACKAGE_FORMAT_PISI,
  OS_PACKAGE_FORMAT_PKGSRC,
  OS_PACKAGE_FORMAT_APK,
  OS_PACKAGE_FORMAT_XBPS,
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
  OS_PACKAGE_MANAGEMENT_DNF,
  OS_PACKAGE_MANAGEMENT_APK,
  OS_PACKAGE_MANAGEMENT_XBPS,
};

enum inspect_os_role {
  OS_ROLE_UNKNOWN = 0,
  OS_ROLE_ROOT,
  OS_ROLE_USR,
};

/**
 * The inspection code maintains one of these structures per mountable
 * filesystem found in the disk image.  The struct (or structs) which
 * have the C<role> attribute set to C<OS_ROLE_ROOT> are inspection roots,
 * each corresponding to a single guest.  Note that a filesystem can be
 * shared between multiple guests.
 */
struct inspect_fs {
  enum inspect_os_role role;
  char *mountable;
  enum inspect_os_type type;
  enum inspect_os_distro distro;
  enum inspect_os_package_format package_format;
  enum inspect_os_package_management package_management;
  char *product_name;
  char *product_variant;
  struct version version;
  char *arch;
  char *hostname;
  char *windows_systemroot;
  char *windows_software_hive;
  char *windows_system_hive;
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

/* handle.c */
extern int guestfs_int_get_backend_setting_bool (guestfs_h *g, const char *name);

/* alloc.c */
extern void *guestfs_int_safe_malloc (guestfs_h *g, size_t nbytes);
extern void *guestfs_int_safe_calloc (guestfs_h *g, size_t n, size_t s);
extern char *guestfs_int_safe_strdup (guestfs_h *g, const char *str);
extern void *guestfs_int_safe_memdup (guestfs_h *g, const void *ptr, size_t size);
extern void *guestfs_int_safe_realloc (guestfs_h *g, void *ptr, size_t nbytes);
extern char *guestfs_int_safe_strdup (guestfs_h *g, const char *str);
extern char *guestfs_int_safe_strndup (guestfs_h *g, const char *str, size_t n);
extern void *guestfs_int_safe_memdup (guestfs_h *g, const void *ptr, size_t size);
extern char *guestfs_int_safe_asprintf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));

#define safe_calloc guestfs_int_safe_calloc
#define safe_malloc guestfs_int_safe_malloc
#define safe_realloc guestfs_int_safe_realloc
#define safe_strdup guestfs_int_safe_strdup
#define safe_strndup guestfs_int_safe_strndup
#define safe_memdup guestfs_int_safe_memdup
#define safe_asprintf guestfs_int_safe_asprintf

/* errors.c */
extern void guestfs_int_init_error_handler (guestfs_h *g);

extern void guestfs_int_error_errno (guestfs_h *g, int errnum, const char *fs, ...)
  __attribute__((format (printf,3,4)));
extern void guestfs_int_perrorf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));

extern void guestfs_int_warning (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_int_debug (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_int_trace (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));

extern void guestfs_int_print_BufferIn (FILE *out, const char *buf, size_t buf_size);
extern void guestfs_int_print_BufferOut (FILE *out, const char *buf, size_t buf_size);

#define error(g,...) guestfs_int_error_errno((g),0,__VA_ARGS__)
#define perrorf guestfs_int_perrorf
#define warning(g,...) guestfs_int_warning((g),__VA_ARGS__)
#define debug(g,...) \
  do { if ((g)->verbose) guestfs_int_debug ((g),__VA_ARGS__); } while (0)

#define NOT_SUPPORTED(g,errcode,...)                     \
  do {                                                   \
    guestfs_int_error_errno ((g), ENOTSUP, __VA_ARGS__);   \
    return (errcode);                                    \
  }                                                      \
  while (0)

extern void guestfs_int_launch_failed_error (guestfs_h *g);
extern void guestfs_int_unexpected_close_error (guestfs_h *g);
extern void guestfs_int_launch_timeout (guestfs_h *g);
extern void guestfs_int_external_command_failed (guestfs_h *g, int status, const char *cmd_name, const char *extra);

/* actions-support.c */
struct trace_buffer {
  FILE *fp;
  char *buf;
  size_t len;
  bool opened;
};

extern int guestfs_int_check_reply_header (guestfs_h *g, const struct guestfs_message_header *hdr, unsigned int proc_nr, unsigned int serial);
extern int guestfs_int_check_appliance_up (guestfs_h *g, const char *caller);
extern void guestfs_int_trace_open (struct trace_buffer *tb);
extern void guestfs_int_trace_send_line (guestfs_h *g, struct trace_buffer *tb);

/* match.c */
extern int guestfs_int_match (guestfs_h *g, const char *str, const pcre *re);
extern char *guestfs_int_match1 (guestfs_h *g, const char *str, const pcre *re);
extern int guestfs_int_match2 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2);
extern int guestfs_int_match3 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2, char **ret3);
extern int guestfs_int_match4 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2, char **ret3, char **ret4);
extern int guestfs_int_match6 (guestfs_h *g, const char *str, const pcre *re, char **ret1, char **ret2, char **ret3, char **ret4, char **ret5, char **ret6);

#define match guestfs_int_match
#define match1 guestfs_int_match1
#define match2 guestfs_int_match2
#define match3 guestfs_int_match3
#define match4 guestfs_int_match4
#define match6 guestfs_int_match6

/* stringsbuf.c */
struct stringsbuf {
  char **argv;
  size_t size;
  size_t alloc;
};
#define DECLARE_STRINGSBUF(v) \
  struct stringsbuf (v) = { .argv = NULL, .size = 0, .alloc = 0 }

extern void guestfs_int_add_string_nodup (guestfs_h *g, struct stringsbuf *sb, char *str);
extern void guestfs_int_add_string (guestfs_h *g, struct stringsbuf *sb, const char *str);
extern void guestfs_int_add_sprintf (guestfs_h *g, struct stringsbuf *sb, const char *fs, ...)
  __attribute__((format (printf,3,4)));
extern void guestfs_int_end_stringsbuf (guestfs_h *g, struct stringsbuf *sb);

extern void guestfs_int_free_stringsbuf (struct stringsbuf *sb);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE_STRINGSBUF __attribute__((cleanup(guestfs_int_cleanup_free_stringsbuf)))
#else
#define CLEANUP_FREE_STRINGSBUF
#endif
extern void guestfs_int_cleanup_free_stringsbuf (struct stringsbuf *sb);

/* proto.c */
extern int guestfs_int_send (guestfs_h *g, int proc_nr, uint64_t progress_hint, uint64_t optargs_bitmask, xdrproc_t xdrp, char *args);
extern int guestfs_int_recv (guestfs_h *g, const char *fn, struct guestfs_message_header *hdr, struct guestfs_message_error *err, xdrproc_t xdrp, char *ret);
extern int guestfs_int_recv_discard (guestfs_h *g, const char *fn);
extern int guestfs_int_send_file (guestfs_h *g, const char *filename);
extern int guestfs_int_recv_file (guestfs_h *g, const char *filename);
extern int guestfs_int_recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn);
extern void guestfs_int_progress_message_callback (guestfs_h *g, const struct guestfs_progress *message);
extern void guestfs_int_log_message_callback (guestfs_h *g, const char *buf, size_t len);

/* conn-socket.c */
extern struct connection *guestfs_int_new_conn_socket_listening (guestfs_h *g, int daemon_accept_sock, int console_sock);
extern struct connection *guestfs_int_new_conn_socket_connected (guestfs_h *g, int daemon_sock, int console_sock);

/* events.c */
extern void guestfs_int_call_callbacks_void (guestfs_h *g, uint64_t event);
extern void guestfs_int_call_callbacks_message (guestfs_h *g, uint64_t event, const char *buf, size_t buf_len);
extern void guestfs_int_call_callbacks_array (guestfs_h *g, uint64_t event, const uint64_t *array, size_t array_len);

/* tmpdirs.c */
extern int guestfs_int_set_env_tmpdir (guestfs_h *g, const char *envname, const char *tmpdir);
extern int guestfs_int_set_env_runtimedir (guestfs_h *g, const char *envname, const char *runtimedir);
extern int guestfs_int_lazy_make_tmpdir (guestfs_h *g);
extern int guestfs_int_lazy_make_sockdir (guestfs_h *g);
extern char *guestfs_int_make_temp_path (guestfs_h *g, const char *name);
extern char *guestfs_int_lazy_make_supermin_appliance_dir (guestfs_h *g);
extern void guestfs_int_remove_tmpdir (guestfs_h *g);
extern void guestfs_int_remove_sockdir (guestfs_h *g);
extern void guestfs_int_recursive_remove_dir (guestfs_h *g, const char *dir);

/* whole-file.c */
extern int guestfs_int_read_whole_file (guestfs_h *g, const char *filename, char **data_r, size_t *size_r);

/* drives.c */
extern size_t guestfs_int_checkpoint_drives (guestfs_h *g);
extern void guestfs_int_rollback_drives (guestfs_h *g, size_t);
extern void guestfs_int_add_dummy_appliance_drive (guestfs_h *g);
extern void guestfs_int_free_drives (guestfs_h *g);
extern const char *guestfs_int_drive_protocol_to_string (enum drive_protocol protocol);

/* appliance.c */
extern int guestfs_int_build_appliance (guestfs_h *g, char **kernel, char **initrd, char **appliance);

/* appliance-cpu.c */
const char *guestfs_int_get_cpu_model (int kvm);

/* appliance-kcmdline.c */
extern char *guestfs_int_appliance_command_line (guestfs_h *g, const char *appliance_dev, int flags);
#define APPLIANCE_COMMAND_LINE_IS_TCG 1

/* appliance-uefi.c */
extern int guestfs_int_get_uefi (guestfs_h *g, char **code, char **vars, int *flags);

/* launch.c */
extern int64_t guestfs_int_timeval_diff (const struct timeval *x, const struct timeval *y);
extern void guestfs_int_launch_send_progress (guestfs_h *g, int perdozen);
int guestfs_int_create_socketname (guestfs_h *g, const char *filename, char (*sockname)[UNIX_PATH_MAX]);
extern void guestfs_int_register_backend (const char *name, const struct backend_ops *);
extern int guestfs_int_set_backend (guestfs_h *g, const char *method);

/* inspect.c */
extern void guestfs_int_free_inspect_info (guestfs_h *g);
extern char *guestfs_int_download_to_tmp (guestfs_h *g, struct inspect_fs *fs, const char *filename, const char *basename, uint64_t max_size);
extern struct inspect_fs *guestfs_int_search_for_root (guestfs_h *g, const char *root);
extern int guestfs_int_is_partition (guestfs_h *g, const char *partition);

/* inspect-fs.c */
extern int guestfs_int_is_file_nocase (guestfs_h *g, const char *);
extern int guestfs_int_is_dir_nocase (guestfs_h *g, const char *);
extern int guestfs_int_check_for_filesystem_on (guestfs_h *g,
                                              const char *mountable);
extern int guestfs_int_parse_unsigned_int (guestfs_h *g, const char *str);
extern int guestfs_int_parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str);
extern int guestfs_int_parse_major_minor (guestfs_h *g, struct inspect_fs *fs);
extern char *guestfs_int_first_line_of_file (guestfs_h *g, const char *filename);
extern int guestfs_int_first_egrep_of_file (guestfs_h *g, const char *filename, const char *eregex, int iflag, char **ret);
extern void guestfs_int_check_package_format (guestfs_h *g, struct inspect_fs *fs);
extern void guestfs_int_check_package_management (guestfs_h *g, struct inspect_fs *fs);
extern void guestfs_int_merge_fs_inspections (guestfs_h *g, struct inspect_fs *dst, struct inspect_fs *src);

/* inspect-fs-unix.c */
extern int guestfs_int_check_linux_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_linux_usr (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_freebsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_netbsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_openbsd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_hurd_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_minix_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_coreos_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_coreos_usr (guestfs_h *g, struct inspect_fs *fs);

/* inspect-fs-windows.c */
extern char *guestfs_int_case_sensitive_path_silently (guestfs_h *g, const char *);
extern char * guestfs_int_get_windows_systemroot (guestfs_h *g);
extern int guestfs_int_check_windows_root (guestfs_h *g, struct inspect_fs *fs, char *windows_systemroot);

/* inspect-fs-cd.c */
extern int guestfs_int_check_installer_root (guestfs_h *g, struct inspect_fs *fs);
extern int guestfs_int_check_installer_iso (guestfs_h *g, struct inspect_fs *fs, const char *device);

/* dbdump.c */
typedef int (*guestfs_int_db_dump_callback) (guestfs_h *g, const unsigned char *key, size_t keylen, const unsigned char *value, size_t valuelen, void *opaque);
extern int guestfs_int_read_db_dump (guestfs_h *g, const char *dumpfile, void *opaque, guestfs_int_db_dump_callback callback);

/* lpj.c */
extern int guestfs_int_get_lpj (guestfs_h *g);

/* fuse.c */
#if HAVE_FUSE
extern void guestfs_int_free_fuse (guestfs_h *g);
#endif

/* libvirt-auth.c */
#ifdef HAVE_LIBVIRT
extern virConnectPtr guestfs_int_open_libvirt_connection (guestfs_h *g, const char *uri, unsigned int flags);
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
  bool is_installer;

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
extern int guestfs_int_osinfo_map (guestfs_h *g, const struct guestfs_isoinfo *isoinfo, const struct osinfo **osinfo_ret);

/* command.c */
struct command;
typedef void (*cmd_stdout_callback) (guestfs_h *g, void *data, const char *line, size_t len);
typedef int (*cmd_child_callback) (guestfs_h *g, void *data);
extern struct command *guestfs_int_new_command (guestfs_h *g);
extern void guestfs_int_cmd_add_arg (struct command *, const char *arg);
extern void guestfs_int_cmd_add_arg_format (struct command *, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_int_cmd_add_string_unquoted (struct command *, const char *str);
extern void guestfs_int_cmd_add_string_quoted (struct command *, const char *str);
extern void guestfs_int_cmd_set_stdout_callback (struct command *, cmd_stdout_callback stdout_callback, void *data, unsigned flags);
#define CMD_STDOUT_FLAG_LINE_BUFFER    0
#define CMD_STDOUT_FLAG_UNBUFFERED      1
#define CMD_STDOUT_FLAG_WHOLE_BUFFER    2
extern void guestfs_int_cmd_set_stderr_to_stdout (struct command *);
extern void guestfs_int_cmd_set_child_rlimit (struct command *, int resource, long limit);
extern void guestfs_int_cmd_clear_capture_errors (struct command *);
extern void guestfs_int_cmd_clear_close_files (struct command *);
extern void guestfs_int_cmd_set_child_callback (struct command *, cmd_child_callback child_callback, void *data);
extern int guestfs_int_cmd_run (struct command *);
extern void guestfs_int_cmd_close (struct command *);
extern int guestfs_int_cmd_pipe_run (struct command *cmd, const char *mode);
extern int guestfs_int_cmd_pipe_wait (struct command *cmd);
extern char *guestfs_int_cmd_get_pipe_errors (struct command *cmd);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_CMD_CLOSE __attribute__((cleanup(guestfs_int_cleanup_cmd_close)))
#else
#define CLEANUP_CMD_CLOSE
#endif
extern void guestfs_int_cleanup_cmd_close (struct command **);

/* launch-*.c constructors */
void guestfs_int_init_direct_backend (void) __attribute__((constructor));
#ifdef HAVE_LIBVIRT_BACKEND
void guestfs_int_init_libvirt_backend (void) __attribute__((constructor));
#endif
void guestfs_int_init_uml_backend (void) __attribute__((constructor));
void guestfs_int_init_unix_backend (void) __attribute__((constructor));

/* qemu.c */
struct qemu_data;
extern struct qemu_data *guestfs_int_test_qemu (guestfs_h *g, struct version *qemu_version);
extern int guestfs_int_qemu_supports (guestfs_h *g, const struct qemu_data *, const char *option);
extern int guestfs_int_qemu_supports_device (guestfs_h *g, const struct qemu_data *, const char *device_name);
extern int guestfs_int_qemu_supports_virtio_scsi (guestfs_h *g, struct qemu_data *, const struct version *qemu_version);
extern char *guestfs_int_drive_source_qemu_param (guestfs_h *g, const struct drive_source *src);
extern bool guestfs_int_discard_possible (guestfs_h *g, struct drive *drv, const struct version *qemu_version);
extern char *guestfs_int_qemu_escape_param (guestfs_h *g, const char *param);
extern void guestfs_int_free_qemu_data (struct qemu_data *);

/* guid.c */
extern int guestfs_int_validate_guid (const char *);

/* umask.c */
extern int guestfs_int_getumask (guestfs_h *g);

/* wait.c */
extern int guestfs_int_waitpid (guestfs_h *g, pid_t pid, int *status, const char *errmsg);
extern void guestfs_int_waitpid_noerror (pid_t pid);
struct rusage;
extern int guestfs_int_wait4 (guestfs_h *g, pid_t pid, int *status, struct rusage *rusage, const char *errmsg);

/* version.c */
extern void guestfs_int_version_from_libvirt (struct version *v, int vernum);
extern void guestfs_int_version_from_values (struct version *v, int maj, int min, int mic);
extern int guestfs_int_version_from_x_y (guestfs_h *g, struct version *v, const char *str);
extern int guestfs_int_version_from_x_y_re (guestfs_h *g, struct version *v, const char *str, const pcre *re);
extern int guestfs_int_version_from_x_y_or_x (guestfs_h *g, struct version *v, const char *str);
extern bool guestfs_int_version_ge (const struct version *v, int maj, int min, int mic);
extern bool guestfs_int_version_cmp_ge (const struct version *a, const struct version *b);
#define version_init_null(v) guestfs_int_version_from_values (v, 0, 0, 0)
#define version_is_null(v) ((v)->v_major == 0 && (v)->v_minor == 0 && (v)->v_micro == 0)

#endif /* GUESTFS_INTERNAL_H_ */
