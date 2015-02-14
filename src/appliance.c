/* libguestfs
 * Copyright (C) 2010-2014 Red Hat Inc.
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

static int build_appliance (guestfs_h *g, char **kernel, char **dtb, char **initrd, char **appliance);
static int find_path (guestfs_h *g, int (*pred) (guestfs_h *g, const char *pelem, void *data), void *data, char **pelem);
static int dir_contains_file (const char *dir, const char *file);
static int dir_contains_files (const char *dir, ...);
static int contains_old_style_appliance (guestfs_h *g, const char *path, void *data);
static int contains_fixed_appliance (guestfs_h *g, const char *path, void *data);
static int contains_supermin_appliance (guestfs_h *g, const char *path, void *data);
static int build_supermin_appliance (guestfs_h *g, const char *supermin_path, uid_t uid, char **kernel, char **dtb, char **initrd, char **appliance);
static int run_supermin_build (guestfs_h *g, const char *lockfile, const char *appliancedir, const char *supermin_path);

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
 * straight to step (3).
 *
 * (2) Call 'supermin --build' to build the full appliance (if it
 * needs to be rebuilt).  If this is successful, return the full
 * appliance.
 *
 * (3) Check each element of g->path, looking for a fixed appliance.
 * If one is found, return it.
 *
 * (4) Check each element of g->path, looking for an old-style appliance.
 * If one is found, return it.
 *
 * The supermin appliance cache directory lives in
 * $TMPDIR/.guestfs-$UID/ and consists of up to five files:
 *
 *   $TMPDIR/.guestfs-$UID/lock         - the supermin lock file
 *   $TMPDIR/.guestfs-$UID/appliance.d/kernel  - the kernel
 *   $TMPDIR/.guestfs-$UID/appliance.d/dtb     - the device tree (on ARM)
 *   $TMPDIR/.guestfs-$UID/appliance.d/initrd  - the supermin initrd
 *   $TMPDIR/.guestfs-$UID/appliance.d/root    - the appliance
 *
 * Multiple instances of libguestfs with the same UID may be racing to
 * create an appliance.  However (since supermin >= 5) supermin
 * provides a --lock flag and atomic update of the appliance.d
 * subdirectory.
 */
int
guestfs_int_build_appliance (guestfs_h *g,
                           char **kernel_rtn,
                           char **dtb_rtn,
                           char **initrd_rtn,
                           char **appliance_rtn)
{
  char *kernel = NULL, *dtb = NULL, *initrd = NULL, *appliance = NULL;

  if (build_appliance (g, &kernel, &dtb, &initrd, &appliance) == -1)
    return -1;

  /* Don't assign these until we know we're going to succeed, to avoid
   * the caller double-freeing (RHBZ#983218).
   */
  *kernel_rtn = kernel;
  *dtb_rtn = dtb;
  *initrd_rtn = initrd;
  *appliance_rtn = appliance;
  return 0;
}

static int
build_appliance (guestfs_h *g,
                 char **kernel,
                 char **dtb,
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

  if (r == 1)
    /* Step (2): build supermin appliance. */
    return build_supermin_appliance (g, supermin_path, uid,
                                     kernel, dtb, initrd, appliance);

  /* Step (3). */
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

    /* The dtb file may or may not exist in the fixed appliance. */
    if (dir_contains_file (path, "dtb")) {
      *dtb = safe_malloc (g, len + 3 /* "dtb" */ + 2);
      sprintf (*dtb, "%s/dtb", path);
    }
    else
      *dtb = NULL;
    return 0;
  }

  /* Step (4). */
  r = find_path (g, contains_old_style_appliance, NULL, &path);
  if (r == -1)
    return -1;

  if (r == 1) {
    size_t len = strlen (path);
    *kernel = safe_malloc (g, len + strlen (kernel_name) + 2);
    *dtb = NULL;
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

/* Build supermin appliance from supermin_path to $TMPDIR/.guestfs-$UID.
 *
 * Returns:
 * 0 = built
 * -1 = error (aborts launch)
 */
static int
build_supermin_appliance (guestfs_h *g,
                          const char *supermin_path,
                          uid_t uid,
                          char **kernel, char **dtb,
			  char **initrd, char **appliance)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_cachedir (g);
  struct stat statbuf;
  size_t len;

  /* len must be longer than the length of any pathname we can
   * generate in this function.
   */
  len = strlen (tmpdir) + 128;
  char cachedir[len];
  snprintf (cachedir, len, "%s/.guestfs-%d", tmpdir, uid);
  char lockfile[len];
  snprintf (lockfile, len, "%s/lock", cachedir);
  char appliancedir[len];
  snprintf (appliancedir, len, "%s/appliance.d", cachedir);

  ignore_value (mkdir (cachedir, 0755));
  ignore_value (chmod (cachedir, 0755)); /* RHBZ#921292 */

  /* See if the cache directory exists and passes some simple checks
   * to make sure it has not been tampered with.
   */
  if (lstat (cachedir, &statbuf) == -1)
    return 0;
  if (statbuf.st_uid != uid) {
    error (g, _("security: cached appliance %s is not owned by UID %d"),
           cachedir, uid);
    return -1;
  }
  if (!S_ISDIR (statbuf.st_mode)) {
    error (g, _("security: cached appliance %s is not a directory (mode %o)"),
           cachedir, statbuf.st_mode);
    return -1;
  }
  if ((statbuf.st_mode & 0022) != 0) {
    error (g, _("security: cached appliance %s is writable by group or other (mode %o)"),
           cachedir, statbuf.st_mode);
    return -1;
  }

  (void) utimes (cachedir, NULL);
  if (g->verbose)
    guestfs_int_print_timestamped_message (g, "begin building supermin appliance");

  /* Build the appliance if it needs to be built. */
  if (g->verbose)
    guestfs_int_print_timestamped_message (g, "run supermin");

  if (run_supermin_build (g, lockfile, appliancedir, supermin_path) == -1)
    return -1;

  if (g->verbose)
    guestfs_int_print_timestamped_message (g, "finished building supermin appliance");

  /* Return the appliance filenames. */
  *kernel = safe_malloc (g, len);
#ifdef DTB_WILDCARD
  *dtb = safe_malloc (g, len);
#else
  *dtb = NULL;
#endif
  *initrd = safe_malloc (g, len);
  *appliance = safe_malloc (g, len);
  snprintf (*kernel, len, "%s/kernel", appliancedir);
#ifdef DTB_WILDCARD
  snprintf (*dtb, len, "%s/dtb", appliancedir);
#endif
  snprintf (*initrd, len, "%s/initrd", appliancedir);
  snprintf (*appliance, len, "%s/root", appliancedir);

  /* Touch the files so they don't get deleted (as they are in /var/tmp). */
  (void) utimes (*kernel, NULL);
#ifdef DTB_WILDCARD
  (void) utimes (*dtb, NULL);
#endif
  (void) utimes (*initrd, NULL);

  /* Checking backend != "uml" is a big hack.  UML encodes the mtime
   * of the original backing file (in this case, the appliance) in the
   * COW file, and checks it when adding it to the VM.  If there are
   * multiple threads running and one touches the appliance here, it
   * will disturb the mtime and UML will give an error.
   *
   * We can get rid of this hack as soon as UML fixes the
   * ubdN=cow,original parsing bug, since we won't need to run
   * uml_mkcow separately, so there is no possible race.
   *
   * XXX
   */
  if (STRNEQ (g->backend, "uml"))
    (void) utimes (*appliance, NULL);

  return 0;
}

/* Run supermin --build and tell it to generate the
 * appliance.
 */
static int
run_supermin_build (guestfs_h *g,
                    const char *lockfile,
                    const char *appliancedir,
                    const char *supermin_path)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
#if 0                           /* not supported in supermin 5 yet XXX */
  uid_t uid = getuid ();
  uid_t euid = geteuid ();
  gid_t gid = getgid ();
  gid_t egid = getegid ();
  int pass_u_g_args = uid != euid || gid != egid;
#endif

  guestfs_int_cmd_add_arg (cmd, SUPERMIN);
  guestfs_int_cmd_add_arg (cmd, "--build");
  if (g->verbose)
    guestfs_int_cmd_add_arg (cmd, "--verbose");
  guestfs_int_cmd_add_arg (cmd, "--if-newer");
  guestfs_int_cmd_add_arg (cmd, "--lock");
  guestfs_int_cmd_add_arg (cmd, lockfile);
#if 0
  if (pass_u_g_args) {
    guestfs_int_cmd_add_arg (cmd, "-u");
    guestfs_int_cmd_add_arg_format (cmd, "%d", euid);
    guestfs_int_cmd_add_arg (cmd, "-g");
    guestfs_int_cmd_add_arg_format (cmd, "%d", egid);
  }
#endif
  guestfs_int_cmd_add_arg (cmd, "--copy-kernel");
  guestfs_int_cmd_add_arg (cmd, "-f");
  guestfs_int_cmd_add_arg (cmd, "ext2");
  guestfs_int_cmd_add_arg (cmd, "--host-cpu");
  guestfs_int_cmd_add_arg (cmd, host_cpu);
#ifdef DTB_WILDCARD
  guestfs_int_cmd_add_arg (cmd, "--dtb");
  guestfs_int_cmd_add_arg (cmd, DTB_WILDCARD);
#endif
  guestfs_int_cmd_add_arg_format (cmd, "%s/supermin.d", supermin_path);
  guestfs_int_cmd_add_arg (cmd, "-o");
  guestfs_int_cmd_add_arg (cmd, appliancedir);

  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, SUPERMIN, NULL);
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
    len = strcspn (pelem, PATH_SEPARATOR);

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

    if (pelem[len] == PATH_SEPARATOR[0])
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

#ifdef __aarch64__

#define AAVMF_DIR "/usr/share/AAVMF"

/* Return the location of firmware needed to boot the appliance.  This
 * is aarch64 only currently, since that's the only architecture where
 * UEFI is mandatory (and that only for RHEL).
 *
 * '*code' is initialized with the path to the read-only UEFI code
 * file.  '*vars' is initialized with the path to a copy of the UEFI
 * vars file (which is cleaned up automatically on exit).
 *
 * If *code == *vars == NULL then no UEFI firmware is available.
 *
 * '*code' and '*vars' should be freed by the caller.
 *
 * If the function returns -1 then there was a real error which should
 * cause appliance building to fail (no UEFI firmware is not an
 * error).
 */
int
guestfs_int_get_uefi (guestfs_h *g, char **code, char **vars)
{
  if (access (AAVMF_DIR "/AAVMF_CODE.fd", R_OK) == 0 &&
      access (AAVMF_DIR "/AAVMF_VARS.fd", R_OK) == 0) {
    CLEANUP_CMD_CLOSE struct command *copycmd = guestfs_int_new_command (g);
    char *varst;
    int r;

    /* Make a copy of AAVMF_VARS.fd.  You can't just map it into the
     * address space read-only as that triggers a different path
     * inside UEFI.
     */
    varst = safe_asprintf (g, "%s/AAVMF_VARS.fd.%d", g->tmpdir, ++g->unique);
    guestfs_int_cmd_add_arg (copycmd, "cp");
    guestfs_int_cmd_add_arg (copycmd, AAVMF_DIR "/AAVMF_VARS.fd");
    guestfs_int_cmd_add_arg (copycmd, varst);
    r = guestfs_int_cmd_run (copycmd);
    if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0) {
      free (varst);
      return -1;
    }

    /* Caller frees. */
    *code = safe_strdup (g, AAVMF_DIR "/AAVMF_CODE.fd");
    *vars = varst;
    return 0;
  }

  *code = *vars = NULL;
  return 0;
}

#else /* !__aarch64__ */

int
guestfs_int_get_uefi (guestfs_h *g, char **code, char **vars)
{
  *code = *vars = NULL;
  return 0;
}

#endif /* !__aarch64__ */
