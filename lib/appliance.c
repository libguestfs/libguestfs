/* libguestfs
 * Copyright (C) 2010-2023 Red Hat Inc.
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
 * This file deals with building the libguestfs appliance.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <libintl.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"

struct appliance_files {
  char *kernel;
  char *initrd;
  char *image;
};

/* Old-style appliance is going to be obsoleted. */
static const char kernel_name[] = "vmlinuz." host_cpu;
static const char initrd_name[] = "initramfs." host_cpu ".img";

static int search_appliance (guestfs_h *g, struct appliance_files *appliance);
static int dir_contains_file (guestfs_h *g, const char *dir, const char *file);
static int dir_contains_files (guestfs_h *g, const char *dir, ...);
static int contains_old_style_appliance (guestfs_h *g, const char *path, void *data);
static int contains_fixed_appliance (guestfs_h *g, const char *path, void *data);
static int contains_supermin_appliance (guestfs_h *g, const char *path, void *data);
static int build_supermin_appliance (guestfs_h *g, const char *supermin_path, struct appliance_files *appliance);
static int run_supermin_build (guestfs_h *g, const char *lockfile, const char *appliancedir, const char *supermin_path);

/**
 * Locate or build the appliance.
 *
 * This function locates or builds the appliance as necessary,
 * handling the supermin appliance, caching of supermin-built
 * appliances, or using either a fixed or old-style appliance.
 *
 * The return value is C<0> = good, C<-1> = error.  Returned in
 * C<appliance.kernel> will be the name of the kernel to use,
 * C<appliance.initrd> the name of the initrd, C<appliance.image> the name of
 * the ext2 root filesystem.  C<appliance.image> can be C<NULL>, meaning that
 * we are using an old-style (non-ext2) appliance.  All three strings must be
 * freed by the caller.  However the referenced files themselves must I<not> be
 * deleted.
 *
 * The process is as follows:
 *
 * =over 4
 *
 * =item 1.
 *
 * Look in C<path> which contains a supermin appliance skeleton.  If no element
 * has this, skip straight to step 3.
 *
 * =item 2.
 *
 * Call C<supermin --build> to build the full appliance (if it needs
 * to be rebuilt).  If this is successful, return the full appliance.
 *
 * =item 3.
 *
 * Check C<path>, looking for a fixed appliance.  If one is found, return it.
 *
 * =item 4.
 *
 * Check C<path>, looking for an old-style appliance.  If one is found,
 * return it.
 *
 * =back
 *
 * The supermin appliance cache directory lives in
 * F<$TMPDIR/.guestfs-$UID/> and consists of up to four files:
 *
 *   $TMPDIR/.guestfs-$UID/lock            - the supermin lock file
 *   $TMPDIR/.guestfs-$UID/appliance.d/kernel - the kernel
 *   $TMPDIR/.guestfs-$UID/appliance.d/initrd - the supermin initrd
 *   $TMPDIR/.guestfs-$UID/appliance.d/root   - the appliance
 *
 * Multiple instances of libguestfs with the same UID may be racing to
 * create an appliance.  However (since supermin E<ge> 5) supermin
 * provides a I<--lock> flag and atomic update of the F<appliance.d>
 * subdirectory.
 */
int
guestfs_int_build_appliance (guestfs_h *g,
			     char **kernel_rtn,
			     char **initrd_rtn,
			     char **appliance_rtn)
{

  struct appliance_files appliance;

  memset (&appliance, 0, sizeof appliance);

  if (search_appliance (g, &appliance) != 1)
    return -1;

  /* Don't assign these until we know we're going to succeed, to avoid
   * the caller double-freeing (RHBZ#983218).
   */
  *kernel_rtn = appliance.kernel;
  *initrd_rtn = appliance.initrd;
  *appliance_rtn = appliance.image;
  return 0;
}

/**
 * Check C<path>, looking for one of appliances: supermin appliance,
 * fixed appliance or old-style appliance.  If one of the fixed appliances is
 * found, return it.  If the supermin appliance skeleton is found, build and
 * return appliance.
 *
 * Return values:
 *
 *   1 = appliance is found, returns C<appliance>,
 *   0 = appliance not found,
 *  -1 = error which aborts the launch process.
 */
static int
locate_or_build_appliance (guestfs_h *g,
                           struct appliance_files *appliance,
                           const char *path)
{
  int r;

  /* Step (1). */
  r = contains_supermin_appliance(g, path, NULL);
  if (r == 1) {
    /* Step (2): build supermin appliance. */
    r = build_supermin_appliance (g, path, appliance);
    return r < 0 ? r : 1;
  }

  /* Step (3). */
  r = contains_fixed_appliance (g, path, NULL);
  if (r == 1) {
    appliance->kernel = safe_asprintf (g, "%s/kernel", path);
    appliance->initrd = safe_asprintf (g, "%s/initrd", path);
    appliance->image = safe_asprintf(g, "%s/root", path);
    return 1;
  }

  /* Step (4). */
  r = contains_old_style_appliance (g, path, NULL);
  if (r == 1) {
    appliance->kernel = safe_asprintf(g, "%s/%s", path, kernel_name);
    appliance->initrd = safe_asprintf(g, "%s/%s", path, initrd_name);
    appliance->image = NULL;
    return 1;
  }

  return 0;
}


/**
 * Search elements of C<g-E<gt>path>, returning the first C<appliance> element
 * which matches the predicate function C<locate_or_build_appliance>.
 *
 * Return values:
 *
 *   1 = a path element matched, returns C<appliance>,
 *   0 = no path element matched,
 *  -1 = error which aborts the launch process.
 */
static int
search_appliance (guestfs_h *g, struct appliance_files *appliance)
{
  const char *pelem = g->path;

  /* Note that if g->path is an empty string, we want to check the
   * current directory (for backwards compatibility with
   * libguestfs < 1.5.4).
   */
  do {
    size_t len = strcspn (pelem, PATH_SEPARATOR);
    /* Empty element or "." means current directory. */
    CLEANUP_FREE char *path = (len == 0) ? safe_strdup (g, ".") :
                                           safe_strndup (g, pelem, len);
    int r = locate_or_build_appliance (g, appliance, path);
    if (r != 0)
      return r;       /* error or predicate matched */

    if (pelem[len] == PATH_SEPARATOR[0])
      pelem += len + 1;
    else
      pelem += len;
  } while (*pelem);

  /* Predicate didn't match on any path element. */
  error (g, _("cannot find any suitable libguestfs supermin, fixed or old-style appliance on LIBGUESTFS_PATH (search path: %s)"),
         g->path);
  return 0;
}

static int
contains_old_style_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (g, path, kernel_name, initrd_name, NULL);
}

static int
contains_fixed_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (g, path,
                             "README.fixed",
                             "kernel", "initrd", "root", NULL);
}

static int
contains_supermin_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (g, path,
                             "supermin.d/base.tar.gz",
                             "supermin.d/packages", NULL);
}

/**
 * Build supermin appliance from C<supermin_path> to
 * F<$TMPDIR/.guestfs-$UID>.
 *
 * Returns: C<0> = built or C<-1> = error (aborts launch).
 */
static int
build_supermin_appliance (guestfs_h *g,
                          const char *supermin_path,
                          struct appliance_files *appliance)
{
  CLEANUP_FREE char *cachedir = NULL, *lockfile = NULL, *appliancedir = NULL;

  cachedir = guestfs_int_lazy_make_supermin_appliance_dir (g);
  if (cachedir == NULL)
    return -1;

  appliancedir = safe_asprintf (g, "%s/appliance.d", cachedir);
  lockfile = safe_asprintf (g, "%s/lock", cachedir);

  debug (g, "begin building supermin appliance");

  /* Build the appliance if it needs to be built. */
  debug (g, "run supermin");

  if (run_supermin_build (g, lockfile, appliancedir, supermin_path) == -1)
    return -1;

  debug (g, "finished building supermin appliance");

  /* Return the appliance filenames. */
  appliance->kernel = safe_asprintf (g, "%s/kernel", appliancedir);
  appliance->initrd = safe_asprintf (g, "%s/initrd", appliancedir);
  appliance->image = safe_asprintf (g, "%s/root", appliancedir);

  /* Touch the files so they don't get deleted (as they are in /var/tmp). */
  (void) utimes (appliance->kernel, NULL);
  (void) utimes (appliance->initrd, NULL);
  (void) utimes (appliance->image, NULL);

  return 0;
}

/**
 * Run C<supermin --build> and tell it to generate the appliance.
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
  const uid_t uid = getuid ();
  const uid_t euid = geteuid ();
  const gid_t gid = getgid ();
  const gid_t egid = getegid ();
  const int pass_u_g_args = uid != euid || gid != egid;
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

/**
 * Returns true iff C<file> is contained in C<dir>.
 */
static int
dir_contains_file (guestfs_h *g, const char *dir, const char *file)
{
  CLEANUP_FREE char *path = NULL;

  path = safe_asprintf (g, "%s/%s", dir, file);
  return access (path, F_OK) == 0;
}

/**
 * Returns true iff every listed file is contained in C<dir>.
 */
static int
dir_contains_files (guestfs_h *g, const char *dir, ...)
{
  va_list args;
  const char *file;

  va_start (args, dir);
  while ((file = va_arg (args, const char *)) != NULL) {
    if (!dir_contains_file (g, dir, file)) {
      va_end (args);
      return 0;
    }
  }
  va_end (args);
  return 1;
}
