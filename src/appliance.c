/* libguestfs
 * Copyright (C) 2010-2011 Red Hat Inc.
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
#include <sys/wait.h>
#include <utime.h>

#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Old-style appliance is going to be obsoleted. */
static const char *kernel_name = "vmlinuz." host_cpu;
static const char *initrd_name = "initramfs." host_cpu ".img";

static int find_path (guestfs_h *g, int (*pred) (guestfs_h *g, const char *pelem, void *data), void *data, char **pelem);
static int dir_contains_file (const char *dir, const char *file);
static int dir_contains_files (const char *dir, ...);
static int contains_ordinary_appliance (guestfs_h *g, const char *path, void *data);
static int contains_supermin_appliance (guestfs_h *g, const char *path, void *data);
static char *calculate_supermin_checksum (guestfs_h *g, const char *supermin_path);
static int check_for_cached_appliance (guestfs_h *g, const char *supermin_path, const char *checksum, uid_t uid, char **kernel, char **initrd, char **appliance);
static int build_supermin_appliance (guestfs_h *g, const char *supermin_path, const char *checksum, uid_t uid, char **kernel, char **initrd, char **appliance);
static int hard_link_to_cached_appliance (guestfs_h *g, const char *cachedir, char **kernel, char **initrd, char **appliance);
static int run_supermin_helper (guestfs_h *g, const char *supermin_path, const char *cachedir, size_t cdlen);
static void print_febootstrap_command_line (guestfs_h *g, const char *argv[]);

/* Locate or build the appliance.
 *
 * This function locates or builds the appliance as necessary,
 * handling the supermin appliance, caching of supermin-built
 * appliances, or using an ordinary appliance.
 *
 * The return value is 0 = good, -1 = error.  Returned in '*kernel'
 * will be the name of the kernel to use, '*initrd' the name of the
 * initrd, '*appliance' the name of the ext2 root filesystem.
 * '*appliance' can be NULL, meaning that we are using an ordinary
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
 * (5) Check each element of g->path, looking for an ordinary appliance.
 * If one is found, return it.
 *
 * The supermin appliance cache directory lives in
 * $TMPDIR/.guestfs-$UID/ and consists of four files:
 *
 *   $TMPDIR/.guestfs-$UID/checksum       - the checksum
 *   $TMPDIR/.guestfs-$UID/kernel         - symlink to the kernel
 *   $TMPDIR/.guestfs-$UID/initrd         - the febootstrap initrd
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
                           char **kernel, char **initrd, char **appliance)
{
  int r;
  uid_t uid = geteuid ();

  /* Step (1). */
  char *supermin_path;
  r = find_path (g, contains_supermin_appliance, NULL, &supermin_path);
  if (r == -1)
    return -1;

  if (r == 1) {
    /* Step (2): calculate checksum. */
    char *checksum = calculate_supermin_checksum (g, supermin_path);
    if (checksum) {
      /* Step (3): cached appliance exists? */
      r = check_for_cached_appliance (g, supermin_path, checksum, uid,
                                      kernel, initrd, appliance);
      if (r != 0) {
        free (supermin_path);
        free (checksum);
        return r == 1 ? 0 : -1;
      }

      /* Step (4): build supermin appliance. */
      r = build_supermin_appliance (g, supermin_path, checksum, uid,
                                    kernel, initrd, appliance);
      free (supermin_path);
      free (checksum);
      return r;
    }
    free (supermin_path);
  }

  /* Step (5). */
  char *path;
  r = find_path (g, contains_ordinary_appliance, NULL, &path);
  if (r == -1)
    return -1;

  if (r == 1) {
    size_t len = strlen (path);
    *kernel = safe_malloc (g, len + strlen (kernel_name) + 2);
    *initrd = safe_malloc (g, len + strlen (initrd_name) + 2);
    sprintf (*kernel, "%s/%s", path, kernel_name);
    sprintf (*initrd, "%s/%s", path, initrd_name);
    *appliance = NULL;

    free (path);
    return 0;
  }

  error (g, _("cannot find any suitable libguestfs supermin or ordinary appliance on LIBGUESTFS_PATH (search path: %s)"),
         g->path);
  return -1;
}

static int
contains_ordinary_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (path, kernel_name, initrd_name, NULL);
}

static int
contains_supermin_appliance (guestfs_h *g, const char *path, void *data)
{
  return dir_contains_files (path, "supermin.d", NULL);
}

/* supermin_path is a path which is known to contain a supermin
 * appliance.  Using febootstrap-supermin-helper -f checksum calculate
 * the checksum so we can see if it is cached.
 */
static char *
calculate_supermin_checksum (guestfs_h *g, const char *supermin_path)
{
  size_t len = 2 * strlen (supermin_path) + 256;
  char cmd[len];
  int pass_u_g_args = getuid () != geteuid () || getgid () != getegid ();

  if (!pass_u_g_args)
    snprintf (cmd, len,
              "febootstrap-supermin-helper%s "
              "-f checksum "
              "'%s/supermin.d' "
              host_cpu,
              g->verbose ? " --verbose" : "",
              supermin_path);
  else
    snprintf (cmd, len,
              "febootstrap-supermin-helper%s "
              "-u %i "
              "-g %i "
              "-f checksum "
              "'%s/supermin.d' "
              host_cpu,
              g->verbose ? " --verbose" : "",
              geteuid (), getegid (),
              supermin_path);

  if (g->verbose)
    guestfs___print_timestamped_message (g, "%s", cmd);

  /* Errors here are non-fatal, so we don't need to call error(). */
  FILE *pp = popen (cmd, "r");
  if (pp == NULL)
    return NULL;

  char checksum[256];
  if (fgets (checksum, sizeof checksum, pp) == NULL) {
    pclose (pp);
    return NULL;
  }

  if (pclose (pp) != 0) {
    warning (g, "pclose: %m");
    return NULL;
  }

  len = strlen (checksum);

  if (len < 16) {               /* sanity check */
    warning (g, "febootstrap-supermin-helper -f checksum returned a short string");
    return NULL;
  }

  if (len > 0 && checksum[len-1] == '\n')
    checksum[--len] = '\0';

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
  const char *tmpdir = guestfs___persistent_tmpdir ();

  /* len must be longer than the length of any pathname we can
   * generate in this function.
   */
  size_t len = strlen (tmpdir) + 128;
  char cachedir[len];
  snprintf (cachedir, len, "%s/.guestfs-%d", tmpdir, uid);
  char filename[len];
  snprintf (filename, len, "%s/checksum", cachedir);

  (void) mkdir (cachedir, 0755);

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
  int fd = open (filename, O_RDONLY);
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
  if (g->verbose)
    guestfs___print_timestamped_message (g, "begin building supermin appliance");

  const char *tmpdir = guestfs___persistent_tmpdir ();

  /* len must be longer than the length of any pathname we can
   * generate in this function.
   */
  size_t len = strlen (tmpdir) + 128;

  /* Build the appliance into a temporary directory. */
  char tmpcd[len];
  snprintf (tmpcd, len, "%s/guestfs.XXXXXX", tmpdir);

  if (mkdtemp (tmpcd) == NULL) {
    perrorf (g, "mkdtemp");
    return -1;
  }

  if (g->verbose)
    guestfs___print_timestamped_message (g, "run febootstrap-supermin-helper");

  int r = run_supermin_helper (g, supermin_path, tmpcd, len);
  if (r == -1) {
    guestfs___remove_tmpdir (tmpcd);
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
  int fd = open (filename, O_WRONLY|O_CREAT, 0755);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    guestfs___remove_tmpdir (tmpcd);
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
    guestfs___remove_tmpdir (tmpcd);
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
    guestfs___remove_tmpdir (tmpcd);
    return -1;
  }

  ssize_t rr = write (fd, checksum, clen);
  if (rr == -1) {
    perrorf (g, "write: %s", filename);
    close (fd);
    guestfs___remove_tmpdir (tmpcd);
    return -1;
  }
  if ((size_t) rr != clen) {
    error (g, "partial write: %s", filename);
    close (fd);
    guestfs___remove_tmpdir (tmpcd);
    return -1;
  }

  snprintf (filename, len, "%s/kernel", tmpcd);
  snprintf (filename2, len, "%s/kernel", cachedir);
  unlink (filename2);
  if (rename (filename, filename2) == -1) {
    perrorf (g, "rename: %s %s", filename, filename2);
    close (fd);
    guestfs___remove_tmpdir (tmpcd);
    return -1;
  }

  snprintf (filename, len, "%s/initrd", tmpcd);
  snprintf (filename2, len, "%s/initrd", cachedir);
  unlink (filename2);
  if (rename (filename, filename2) == -1) {
    perrorf (g, "rename: %s %s", filename, filename2);
    close (fd);
    guestfs___remove_tmpdir (tmpcd);
    return -1;
  }

  snprintf (filename, len, "%s/root", tmpcd);
  snprintf (filename2, len, "%s/root", cachedir);
  unlink (filename2);
  if (rename (filename, filename2) == -1) {
    perrorf (g, "rename: %s %s", filename, filename2);
    close (fd);
    guestfs___remove_tmpdir (tmpcd);
    return -1;
  }

  guestfs___remove_tmpdir (tmpcd);

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
  (void) lutimes (filename, NULL); /* lutimes because it's a symlink */

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

/* Run febootstrap-supermin-helper and tell it to generate the
 * appliance.
 */
static int
run_supermin_helper (guestfs_h *g, const char *supermin_path,
                     const char *cachedir, size_t cdlen)
{
  size_t pathlen = strlen (supermin_path);

  const char *argv[30];
  size_t i = 0;

  char uid[32];
  snprintf (uid, sizeof uid, "%i", geteuid ());
  char gid[32];
  snprintf (gid, sizeof gid, "%i", getegid ());
  char supermin_d[pathlen + 32];
  snprintf (supermin_d, pathlen + 32, "%s/supermin.d", supermin_path);
  char kernel[cdlen + 32];
  snprintf (kernel, cdlen + 32, "%s/kernel", cachedir);
  char initrd[cdlen + 32];
  snprintf (initrd, cdlen + 32, "%s/initrd", cachedir);
  char root[cdlen + 32];
  snprintf (root, cdlen + 32, "%s/root", cachedir);

  int pass_u_g_args = getuid () != geteuid () || getgid () != getegid ();

  argv[i++] = "febootstrap-supermin-helper";
  if (g->verbose)
    argv[i++] = "--verbose";
  if (pass_u_g_args) {
    argv[i++] = "-u";
    argv[i++] = uid;
    argv[i++] = "-g";
    argv[i++] = gid;
  }
  argv[i++] = "-f";
  argv[i++] = "ext2";
  argv[i++] = supermin_d;
  argv[i++] = host_cpu;
  argv[i++] = kernel;
  argv[i++] = initrd;
  argv[i++] = root;
  argv[i++] = NULL;

  if (g->verbose)
    print_febootstrap_command_line (g, argv);

  pid_t pid = fork ();
  if (pid == -1) {
    perrorf (g, "fork");
    return -1;
  }

  if (pid > 0) {                /* Parent. */
    int status;
    if (waitpid (pid, &status, 0) == -1) {
      perrorf (g, "waitpid");
      return -1;
    }
    if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      error (g, _("external command failed, see earlier error messages"));
      return -1;
    }
    return 0;
  }

  /* Child. */

  /* Set a sensible umask in the subprocess, so kernel and initrd
   * output files are world-readable (RHBZ#610880).
   */
  umask (0022);

  execvp ("febootstrap-supermin-helper", (char * const *) argv);
  perror ("execvp");
  _exit (EXIT_FAILURE);
}

static void
print_febootstrap_command_line (guestfs_h *g, const char *argv[])
{
  int i;
  int needs_quote;
  char *buf;
  size_t len;

  /* Calculate length of the buffer needed.  This is an overestimate. */
  len = 0;
  for (i = 0; argv[i] != NULL; ++i)
    len += strlen (argv[i]) + 32;

  buf = malloc (len);
  if (buf == NULL) {
    warning (g, "malloc: %m");
    return;
  }

  len = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0) {
      strcpy (&buf[len], " ");
      len++;
    }

    /* Does it need shell quoting?  This only deals with simple cases. */
    needs_quote = strcspn (argv[i], " ") != strlen (argv[i]);

    if (needs_quote) {
      strcpy (&buf[len], "'");
      len++;
    }

    strcpy (&buf[len], argv[i]);
    len += strlen (argv[i]);

    if (needs_quote) {
      strcpy (&buf[len], "'");
      len++;
    }
  }

  guestfs___print_timestamped_message (g, "%s", buf);

  free (buf);
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
