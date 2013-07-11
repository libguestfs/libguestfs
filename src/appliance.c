/* libguestfs
 * Copyright (C) 2010-2012 Red Hat Inc.
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

#include <config.h>

#include <errno.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <utime.h>

#include "glthread/lock.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Old-style appliance is going to be obsoleted. */
static const char *kernel_name = "vmlinuz." host_cpu;
static const char *initrd_name = "initramfs." host_cpu ".img";

static int build_appliance (guestfs_h *g, char **kernel, char **initrd, char **appliance);
static int find_path (guestfs_h *g, int (*pred) (guestfs_h *g, const char *pelem, void *data), void *data, char **pelem);
static int dir_contains_file (const char *dir, const char *file);
static int dir_contains_files (const char *dir, ...);
static int contains_old_style_appliance (guestfs_h *g, const char *path, void *data);
static int contains_fixed_appliance (guestfs_h *g, const char *path, void *data);
static int contains_supermin_appliance (guestfs_h *g, const char *path, void *data);
static char *calculate_supermin_checksum (guestfs_h *g, const char *supermin_path);
static int check_for_cached_appliance (guestfs_h *g, const char *supermin_path, const char *checksum, uid_t uid, char **kernel, char **initrd, char **appliance);
static int build_supermin_appliance (guestfs_h *g, const char *supermin_path, const char *checksum, uid_t uid, char **kernel, char **initrd, char **appliance);
static int hard_link_to_cached_appliance (guestfs_h *g, const char *cachedir, char **kernel, char **initrd, char **appliance);
static int run_supermin_helper (guestfs_h *g, const char *supermin_path, const char *cachedir);

/* RHBZ#790721: It makes no sense to have multiple threads racing to
 * build the appliance from within a single process, and the code
 * isn't safe for that anyway.  Therefore put a thread lock around
 * appliance building.
 */
gl_lock_define_initialized (static, building_lock);

/* Locate or build the appliance.
 *
 * This function locates or builds the appliance as necessary,
 * handling the supermin appliance, caching of supermin-built
 * appliances, or using either a fixed or old-style appliance.
 *
 * The return value is 0 = good, -1 = error.  Returned in '*kernel'
 * will be the name of the kernel to use, '*initrd' the name of the
 * initrd, '*appliance' the name of the ext2 root filesystem.
 * '*appliance' can be NULL, meaning that we are using an old-style
 * (non-ext2) appliance.  All three strings must be freed by the
 * caller.  However the referenced files themselves must not be
 * deleted.
 *
 * The process is as follows:
 *
 * (1) Look for the first element of g->path which contains a
 * supermin appliance skeleton.  If no element has this, skip
 * straight to step (5).
 *
 * (2) Calculate the checksum of this supermin appliance.
 *
 * (3) Check whether a cached appliance with the checksum calculated
 * in (2) exists and passes basic security checks.  If so, return
 * this appliance.
 *
 * (4) Try to build the supermin appliance.  If this is successful,
 * return it.
 *
 * (5) Check each element of g->path, looking for a fixed appliance.
 * If one is found, return it.
 *
 * (6) Check each element of g->path, looking for an old-style appliance.
 * If one is found, return it.
 *
 * The supermin appliance cache directory lives in
 * $TMPDIR/.guestfs-$UID/ and consists of four files:
 *
 *   $TMPDIR/.guestfs-$UID/checksum       - the checksum
 *   $TMPDIR/.guestfs-$UID/kernel         - the kernel
 *   $TMPDIR/.guestfs-$UID/initrd         - the supermin initrd
 *   $TMPDIR/.guestfs-$UID/root           - the appliance
 *
 * Since multiple instances of libguestfs with the same UID may be
 * racing to create an appliance, we need to be careful when building
 * and using the appliance.
 *
 * If a cached appliance with checksum exists (step (2) above) then we
 * make a hard link to it with our current PID, so that we have a copy
 * even if the appliance is replaced by another process building an
 * appliance afterwards:
 *
 *   $TMPDIR/.guestfs-$UID/kernel.$PID
 *   $TMPDIR/.guestfs-$UID/initrd.$PID
 *   $TMPDIR/.guestfs-$UID/root.$PID
 *
 * A lock is taken on "checksum" while we perform the link.
 *
 * Linked files are deleted by a garbage collection sweep which can be
 * initiated by any libguestfs process with the same UID when the
 * corresponding PID no longer exists.  (This is safe: the parent is
 * always around in guestfs_launch() while qemu is starting up, and
 * after that qemu will either have finished with the files or be
 * holding them open, so we can unlink them).
 *
 * When building a new appliance (step (3)), it is built into randomly
 * named temporary files in the $TMPDIR.  Then a lock is acquired on
 * $TMPDIR/.guestfs-$UID/checksum (this file being created if
 * necessary), the files are renamed into their final location, and
 * the lock is released.
 */
int
guestfs___build_appliance (guestfs_h *g,
                           char **kernel_rtn,
                           char **initrd_rtn,
                           char **appliance_rtn)
{
  int r;
  char *kernel, *initrd, *appliance;

  gl_lock_lock (building_lock);
  r = build_appliance (g, &kernel, &initrd, &appliance);
  gl_lock_unlock (building_lock);

  if (r == -1)
    return -1;

  /* Don't assign these until we know we're going to succeed, to avoid
   * the caller double-freeing (RHBZ#983218).
   */
  *kernel_rtn = kernel;
  *initrd_rtn = initrd;
  *appliance_rtn = appliance;
  return 0;
}

static int
build_appliance (guestfs_h *g,
                 char **kernel,
                 char **initrd,
                 char **appliance)
{
  int r;
  uid_t uid = geteuid ();
  CLEANUP_FREE char *supermin_path = NULL;
  CLEANUP_FREE char *path = NULL;

  /* Step (1). */
  r = find_path (g, contains_supermin_appliance, NULL, &supermin_path);
  if (r == -1)
    return -1;

  if (r == 1) {
    /* Step (2): calculate checksum. */
    CLEANUP_FREE char *checksum =
      calculate_supermin_checksum (g, supermin_path);
    if (checksum) {
      /* Step (3): cached appliance exists? */
      r = check_for_cached_appliance (g, supermin_path, checksum, uid,
                                      kernel, initrd, appliance);
      if (r != 0)
        return r == 1 ? 0 : -1;

      /* Step (4): build supermin appliance. */
      return build_supermin_appliance (g, supermin_path, checksum, uid,
                                       kernel, initrd, appliance);
    }
  }

  /* Step (5). */
  r = find_path (g, contains_fixed_appliance, NULL, &path);
  if (r == -1)
    return -1;

  if (r == 1) {
    size_t len = strlen (path);
    *kernel = safe_malloc (g, len + 6 /* "kernel" */ + 2);
    *initrd = safe_malloc (g, len + 6 /* "initrd" */ + 2);
    *appliance = safe_malloc (g, len + 4 /* "root" */ + 2);
    sprintf (*kernel, "%s/kernel", path);
    sprintf (*initrd, "%s/initrd", path);
    sprintf (*appliance, "%s/root", path);
    return 0;
  }

  /* Step (6). */
  r = find_path (g, contains_old_style_appliance, NULL, &path);
  if (r == -1)
    return -1;

  if (r == 1) {
    size_t len = strlen (path);
    *kernel = safe_malloc (g, len + strlen (kernel_name) + 2);
    *initrd = safe_malloc (g, len + strlen (initrd_name) + 2);
    sprintf (*kernel, "%s/%s", path, kernel_name);
    sprintf (*initrd, "%s/%s", path, initrd_name);
    *appliance = NULL;
    return 0;
  }

  error (g, _("cannot find any suitable libguestfs supermin, fixed or old-style appliance on LIBGUESTFS_PATH (search path: %s)"),
         g->path);
  return -1;
}

static int
contains_old_style_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (path, kernel_name, initrd_name, NULL);
}

static int
contains_fixed_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (path,
                             "README.fixed",
                             "kernel", "initrd", "root", NULL);
}

static int
contains_supermin_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (path, "supermin.d", NULL);
}

#define MAX_CHECKSUM_LEN 256

static void
read_checksum (guestfs_h *g, void *checksumv, const char *line, size_t len)
{
  char *checksum = checksumv;

  if (len > MAX_CHECKSUM_LEN)
    return;
  strcpy (checksum, line);
}

/* supermin_path is a path which is known to contain a supermin
 * appliance.  Using supermin-helper -f checksum calculate
 * the checksum so we can see if it is cached.
 */
static char *
calculate_supermin_checksum (guestfs_h *g, const char *supermin_path)
{
  size_t len;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs___new_command (g);
  int pass_u_g_args = getuid () != geteuid () || getgid () != getegid ();
  char checksum[MAX_CHECKSUM_LEN + 1] = { 0 };

  guestfs___cmd_add_arg (cmd, SUPERMIN_HELPER);
  if (g->verbose)
    guestfs___cmd_add_arg (cmd, "--verbose");
  if (pass_u_g_args) {
    guestfs___cmd_add_arg (cmd, "-u");
    guestfs___cmd_add_arg_format (cmd, "%d", geteuid ());
    guestfs___cmd_add_arg (cmd, "-g");
    guestfs___cmd_add_arg_format (cmd, "%d", getegid ());
  }
  guestfs___cmd_add_arg (cmd, "-f");
  guestfs___cmd_add_arg (cmd, "checksum");
  guestfs___cmd_add_arg_format (cmd, "%s/supermin.d", supermin_path);
  guestfs___cmd_add_arg (cmd, host_cpu);
  guestfs___cmd_set_stdout_callback (cmd, read_checksum, checksum, 0);

  /* Errors here are non-fatal, so we don't need to call error(). */
  if (guestfs___cmd_run (cmd) == -1)
    return NULL;

  debug (g, "checksum of existing appliance: %s", checksum);

  len = strlen (checksum);
  if (len < 16) {               /* sanity check */
    warning (g, "supermin-helper -f checksum returned a short string");
    return NULL;
  }

  return safe_strndup (g, checksum, len);
}

static int
process_exists (int pid)
{
  if (kill (pid, 0) == 0)
    return 1;

  if (errno == ESRCH)
    return 0;

  return -1;
}

/* Garbage collect appliance hard links.  Files that match
 * (kernel|initrd|root).$PID where the corresponding PID doesn't exist
 * are deleted.  Note that errors in this function don't matter.
 * There may also be other libguestfs processes racing to do the same
 * thing here.
 */
static void
garbage_collect_appliances (const char *cachedir)
{
  DIR *dir;
  struct dirent *d;
  int pid;

  dir = opendir (cachedir);
  if (dir == NULL)
    return;

  while ((d = readdir (dir)) != NULL) {
    if (sscanf (d->d_name, "kernel.%d", &pid) == 1 &&
        process_exists (pid) == 0)
      unlinkat (dirfd (dir), d->d_name, 0);
    else if (sscanf (d->d_name, "initrd.%d", &pid) == 1 &&
             process_exists (pid) == 0)
      unlinkat (dirfd (dir), d->d_name, 0);
    else if (sscanf (d->d_name, "root.%d", &pid) == 1 &&
             process_exists (pid) == 0)
      unlinkat (dirfd (dir), d->d_name, 0);
  }

  closedir (dir);
}

static int
check_for_cached_appliance (guestfs_h *g,
                            const char *supermin_path, const char *checksum,
                            uid_t uid,
                            char **kernel, char **initrd, char **appliance)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_cachedir (g);

  /* len must be longer than the length of any pathname we can
   * generate in this function.
   */
  size_t len = strlen (tmpdir) + 128;
  char cachedir[len];
  snprintf (cachedir, len, "%s/.guestfs-%d", tmpdir, uid);
  char filename[len];
  snprintf (filename, len, "%s/checksum", cachedir);

  ignore_value (mkdir (cachedir, 0755));
  ignore_value (chmod (cachedir, 0755)); /* RHBZ#921292 */

  /* See if the cache directory exists and passes some simple checks
   * to make sure it has not been tampered with.
   */
  struct stat statbuf;
  if (lstat (cachedir, &statbuf) == -1)
    return 0;
  if (statbuf.st_uid != uid) {
    error (g, _("security: cached appliance %s is not owned by UID %d"),
           filename, uid);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    error (g, _("security: cached appliance %s is not a directory (mode %o)"),
           filename, statbuf.st_mode);
    return -1;
  }
  if ((statbuf.st_mode & 0022) != 0) {
    error (g, _("security: cached appliance %s is writable by group or other (mode %o)"),
           cachedir, statbuf.st_mode);
    return -1;
  }

  (void) utime (cachedir, NULL);

  garbage_collect_appliances (cachedir);

  /* Try to open and acquire a lock on the checksum file. */
  int fd = open (filename, O_RDONLY|O_CLOEXEC);
  if (fd == -1)
    return 0;
#ifdef HAVE_FUTIMENS
  (void) futimens (fd, NULL);
#else
  (void) futimes (fd, NULL);
#endif
  struct flock fl;
  fl.l_type = F_RDLCK;
  fl.l_whence = SEEK_SET;
  fl.l_start = 0;
  fl.l_len = 1;
 again:
  if (fcntl (fd, F_SETLKW, &fl) == -1) {
    if (errno == EINTR)
      goto again;
    perrorf (g, "fcntl: F_SETLKW: %s", filename);
    close (fd);
    return -1;
  }

  /* Read the checksum file. */
  size_t clen = strlen (checksum);
  char checksum_on_disk[clen];
  ssize_t rr = read (fd, checksum_on_disk, clen);
  if (rr == -1) {
    perrorf (g, "read: %s", filename);
    close (fd);
    return -1;
  }
  if ((size_t) rr != clen) {
    close (fd);
    return 0;
  }

  if (memcmp (checksum, checksum_on_disk, clen) != 0) {
    close (fd);
    return 0;
  }

  /* At this point, cachedir exists, and checksum matches, and we have
   * a read lock on the checksum file.  Make hard links to the files.
   */
  if (hard_link_to_cached_appliance (g, cachedir,
                                     kernel, initrd, appliance) == -1) {
    close (fd);
    return -1;
  }

  /* Releases the lock on checksum. */
  if (close (fd) == -1) {
    perrorf (g, "close");
    /* Allocated in hard_link_to_cached_appliance above, must be
     * freed along this error path.
     */
    free (*kernel);
    free (*initrd);
    free (*appliance);
    return -1;
  }

  /* Exists! */
  return 1;
}

/* Build supermin appliance from supermin_path to $TMPDIR/.guestfs-$UID.
 *
 * Returns:
 * 0 = built
 * -1 = error (aborts launch)
 */
static int
build_supermin_appliance (guestfs_h *g,
                          const char *supermin_path, const char *checksum,
                          uid_t uid,
                          char **kernel, char **initrd, char **appliance)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_cachedir (g);
  size_t len;

  if (g->verbose)
    guestfs___print_timestamped_message (g, "begin building supermin appliance");

  /* len must be longer than the length of any pathname we can
   * generate in this function.
   */
  len = strlen (tmpdir) + 128;

  /* Build the appliance into a temporary directory. */
  char tmpcd[len];
  snprintf (tmpcd, len, "%s/guestfs.XXXXXX", tmpdir);

  if (mkdtemp (tmpcd) == NULL) {
    perrorf (g, "mkdtemp");
    return -1;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "run supermin-helper");

  int r = run_supermin_helper (g, supermin_path, tmpcd);
  if (r == -1) {
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "finished building supermin appliance");

  char cachedir[len];
  snprintf (cachedir, len, "%s/.guestfs-%d", tmpdir, uid);
  char filename[len];
  char filename2[len];
  snprintf (filename, len, "%s/checksum", cachedir);

  /* Open and acquire write lock on checksum file.  The file might
   * not exist, in which case we want to create it.
   */
  int fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0755);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }
  struct flock fl;
  fl.l_type = F_WRLCK;
  fl.l_whence = SEEK_SET;
  fl.l_start = 0;
  fl.l_len = 1;
 again:
  if (fcntl (fd, F_SETLKW, &fl) == -1) {
    if (errno == EINTR)
      goto again;
    perrorf (g, "fcntl: F_SETLKW: %s", filename);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  /* At this point we have acquired a write lock on the checksum
   * file so we go ahead and replace it with the new checksum, and
   * rename in appliance files into this directory.
   */
  size_t clen = strlen (checksum);
  if (ftruncate (fd, clen) == -1) {
    perrorf (g, "ftruncate: %s", filename);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  ssize_t rr = write (fd, checksum, clen);
  if (rr == -1) {
    perrorf (g, "write: %s", filename);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }
  if ((size_t) rr != clen) {
    error (g, "partial write: %s", filename);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  snprintf (filename, len, "%s/kernel", tmpcd);
  snprintf (filename2, len, "%s/kernel", cachedir);
  unlink (filename2);
  if (rename (filename, filename2) == -1) {
    perrorf (g, "rename: %s %s", filename, filename2);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  snprintf (filename, len, "%s/initrd", tmpcd);
  snprintf (filename2, len, "%s/initrd", cachedir);
  unlink (filename2);
  if (rename (filename, filename2) == -1) {
    perrorf (g, "rename: %s %s", filename, filename2);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  snprintf (filename, len, "%s/root", tmpcd);
  snprintf (filename2, len, "%s/root", cachedir);
  unlink (filename2);
  if (rename (filename, filename2) == -1) {
    perrorf (g, "rename: %s %s", filename, filename2);
    close (fd);
    guestfs___recursive_remove_dir (g, tmpcd);
    return -1;
  }

  guestfs___recursive_remove_dir (g, tmpcd);

  /* Now finish off by linking to the cached appliance and returning it. */
  if (hard_link_to_cached_appliance (g, cachedir,
                                     kernel, initrd, appliance) == -1) {
    close (fd);
    return -1;
  }

  /* Releases the lock on checksum. */
  if (close (fd) == -1) {
    perrorf (g, "close");
    /* Allocated in hard_link_to_cached_appliance above, must be
     * freed along this error path.
     */
    free (*kernel);
    free (*initrd);
    free (*appliance);
    return -1;
  }

  return 0;
}

/* NB: lock on checksum file must be held when this is called. */
static int
hard_link_to_cached_appliance (guestfs_h *g,
                               const char *cachedir,
                               char **kernel, char **initrd, char **appliance)
{
  pid_t pid = getpid ();
  size_t len = strlen (cachedir) + 32;

  *kernel = safe_malloc (g, len);
  *initrd = safe_malloc (g, len);
  *appliance = safe_malloc (g, len);
  snprintf (*kernel, len, "%s/kernel.%d", cachedir, pid);
  snprintf (*initrd, len, "%s/initrd.%d", cachedir, pid);
  snprintf (*appliance, len, "%s/root.%d", cachedir, pid);

  char filename[len];
  snprintf (filename, len, "%s/kernel", cachedir);
  (void) unlink (*kernel);
  if (link (filename, *kernel) == -1) {
    perrorf (g, "link: %s %s", filename, *kernel);
    goto error;
  }
  (void) utimes (filename, NULL);

  snprintf (filename, len, "%s/initrd", cachedir);
  (void) unlink (*initrd);
  if (link (filename, *initrd) == -1) {
    perrorf (g, "link: %s %s", filename, *initrd);
    goto error;
  }
  (void) utime (filename, NULL);

  snprintf (filename, len, "%s/root", cachedir);
  (void) unlink (*appliance);
  if (link (filename, *appliance) == -1) {
    perrorf (g, "link: %s %s", filename, *appliance);
    goto error;
  }
  (void) utime (filename, NULL);

  return 0;

 error:
  free (*kernel);
  free (*initrd);
  free (*appliance);
  return -1;
}

/* Run supermin-helper and tell it to generate the
 * appliance.
 */
static int
run_supermin_helper (guestfs_h *g, const char *supermin_path,
                     const char *cachedir)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs___new_command (g);
  int r;
  uid_t uid = getuid ();
  uid_t euid = geteuid ();
  gid_t gid = getgid ();
  gid_t egid = getegid ();
  int pass_u_g_args = uid != euid || gid != egid;

  guestfs___cmd_add_arg (cmd, SUPERMIN_HELPER);
  if (g->verbose)
    guestfs___cmd_add_arg (cmd, "--verbose");
  if (pass_u_g_args) {
    guestfs___cmd_add_arg (cmd, "-u");
    guestfs___cmd_add_arg_format (cmd, "%d", euid);
    guestfs___cmd_add_arg (cmd, "-g");
    guestfs___cmd_add_arg_format (cmd, "%d", egid);
  }
  guestfs___cmd_add_arg (cmd, "--copy-kernel");
  guestfs___cmd_add_arg (cmd, "-f");
  guestfs___cmd_add_arg (cmd, "ext2");
  guestfs___cmd_add_arg_format (cmd, "%s/supermin.d", supermin_path);
  guestfs___cmd_add_arg (cmd, host_cpu);
  guestfs___cmd_add_arg_format (cmd, "%s/kernel", cachedir);
  guestfs___cmd_add_arg_format (cmd, "%s/initrd", cachedir);
  guestfs___cmd_add_arg_format (cmd, "%s/root", cachedir);

  r = guestfs___cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs___external_command_failed (g, r, SUPERMIN_HELPER, NULL);
    return -1;
  }

  return 0;
}

/* Search elements of g->path, returning the first path element which
 * matches the predicate function 'pred'.
 *
 * Function 'pred' must return a true or false value.  If it returns
 * -1 then the entire search is aborted.
 *
 * Return values:
 * 1 = a path element matched, it is returned in *pelem_ret and must be
 *     freed by the caller,
 * 0 = no path element matched, *pelem_ret is set to NULL, or
 * -1 = error which aborts the launch process
 */
static int
find_path (guestfs_h *g,
           int (*pred) (guestfs_h *g, const char *pelem, void *data),
           void *data,
           char **pelem_ret)
{
  size_t len;
  int r;
  const char *pelem = g->path;

  /* Note that if g->path is an empty string, we want to check the
   * current directory (for backwards compatibility with
   * libguestfs < 1.5.4).
   */
  do {
    len = strcspn (pelem, ":");

    /* Empty element or "." means current directory. */
    if (len == 0)
      *pelem_ret = safe_strdup (g, ".");
    else
      *pelem_ret = safe_strndup (g, pelem, len);

    r = pred (g, *pelem_ret, data);
    if (r == -1) {
      free (*pelem_ret);
      return -1;
    }

    if (r != 0)                 /* predicate matched */
      return 1;

    free (*pelem_ret);

    if (pelem[len] == ':')
      pelem += len + 1;
    else
      pelem += len;
  } while (*pelem);

  /* Predicate didn't match on any path element. */
  *pelem_ret = NULL;
  return 0;
}

/* Returns true iff file is contained in dir. */
static int
dir_contains_file (const char *dir, const char *file)
{
  size_t dirlen = strlen (dir);
  size_t filelen = strlen (file);
  size_t len = dirlen + filelen + 2;
  char path[len];

  snprintf (path, len, "%s/%s", dir, file);
  return access (path, F_OK) == 0;
}

/* Returns true iff every listed file is contained in 'dir'. */
static int
dir_contains_files (const char *dir, ...)
{
  va_list args;
  const char *file;

  va_start (args, dir);
  while ((file = va_arg (args, const char *)) != NULL) {
    if (!dir_contains_file (dir, file)) {
      va_end (args);
      return 0;
    }
  }
  va_end (args);
  return 1;
}
