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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/**
 * Miscellaneous utility functions used by the daemon.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <sys/param.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <errno.h>
#include <error.h>
#include <assert.h>

#include "c-ctype.h"

#include "daemon.h"

#ifndef MAX
# define MAX(a,b) ((a)>(b)?(a):(b))
#endif

/* Not the end of the world if this open flag is not defined. */
#ifndef O_CLOEXEC
# define O_CLOEXEC 0
#endif

/* If root device is an ext2 filesystem, this is the major and minor.
 * This is so we can ignore this device from the point of view of the
 * user, eg. in guestfs_list_devices and many other places.
 */
dev_t root_device = 0;

int verbose = 0;
int enable_network = 0;

/* Location to mount root device. */
const char *sysroot = "/sysroot"; /* No trailing slash. */
size_t sysroot_len = 8;

/* If set (the default), do 'umount-all' when performing autosync. */
int autosync_umount = 1;

/* If set, we are testing the daemon as part of the libguestfs tests. */
int test_mode = 0;

/**
 * Return true iff device is the root device (and therefore should be
 * ignored from the point of view of user calls).
 */
static int
is_root_device_stat (struct stat *statbuf)
{
  if (statbuf->st_rdev == root_device) return 1;
  return 0;
}

int
is_root_device (const char *device)
{
  struct stat statbuf;

  udev_settle_file (device);

  if (stat (device, &statbuf) == -1) {
    perror (device);
    return 0;
  }

  return is_root_device_stat (&statbuf);
}

/**
 * Parameters marked as C<Device>, C<Dev_or_Path>, etc can be passed a
 * block device name.  This function tests if the parameter is a block
 * device name.
 *
 * It can also be used in daemon code to test if the string passed
 * as a C<Dev_or_Path> parameter is a device or path.
 */
int
is_device_parameter (const char *device)
{
  struct stat statbuf;
  CLEANUP_CLOSE int fd = -1;
  uint64_t n;

  udev_settle_file (device);

  if (!STRPREFIX (device, "/dev/"))
    return 0;

  /* Allow any /dev/sd device, so device name translation works. */
  if (STRPREFIX (device, "/dev/sd"))
    return 1;

  /* Is it a block device in the appliance? */
  if (stat (device, &statbuf) == -1) {
    if (verbose)
      fprintf (stderr, "%s: stat: %s: %m\n", "is_device_parameter", device);
    return 0;
  }

  /* Special case: The lvremove API allows you to remove all LVs by
   * pointing to the VG directory.  This was misconceived in the
   * extreme, but here we are.  XXX
   */
  if (S_ISDIR (statbuf.st_mode))
    return strlen (device) > 5;

  if (!S_ISBLK (statbuf.st_mode))
    return 0;

  /* Reject the root (appliance) device. */
  if (is_root_device_stat (&statbuf)) {
    if (verbose)
      fprintf (stderr, "%s: %s is the root device\n",
               "is_device_parameter", device);
    return 0;
  }

  /* Only now is it safe to try opening the device since chardev devices
   * might block when opened.
   *
   * Only disk-like things should support BLKGETSIZE64.
   */
  fd = open (device, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    if (verbose)
      fprintf (stderr, "%s: open: %s: %m\n", "is_device_parameter", device);
    return 0;
  }
  if (ioctl (fd, BLKGETSIZE64, &n) == -1) {
    if (verbose)
      fprintf (stderr, "%s: ioctl BLKGETSIZE64: %s: %m\n",
               "is_device_parameter", device);
    return 0;
  }

  return 1;
}

/**
 * Turn C<"/path"> into C<"/sysroot/path">.
 *
 * Returns C<NULL> on failure.  The caller I<must> check for this and
 * call S<C<reply_with_perror ("malloc")>>.  The caller must also free
 * the returned string.
 *
 * See also the custom C<%R> printf formatter which does shell quoting too.
 */
char *
sysroot_path (const char *path)
{
  char *r;
  const size_t len = strlen (path) + sysroot_len + 1;

  r = malloc (len);
  if (r == NULL)
    return NULL;

  snprintf (r, len, "%s%s", sysroot, path);
  return r;
}

/**
 * Resolve path within sysroot, calling C<sysroot_path> on the
 * resolved path.
 *
 * Returns C<NULL> on failure.  The caller I<must> check for this and
 * call S<C<reply_with_perror ("malloc")>>.  The caller must also free
 * the returned string.
 *
 * See also the custom C<%R> printf formatter which does shell quoting too.
 */
char *
sysroot_realpath (const char *path)
{
  CLEANUP_FREE char *rp = NULL;

  CHROOT_IN;
  rp = realpath (path, NULL);
  CHROOT_OUT;
  if (rp == NULL)
    return NULL;

  return sysroot_path (rp);
}

int
xwrite (int sock, const void *v_buf, size_t len)
{
  ssize_t r;
  const char *buf = v_buf;

  while (len > 0) {
    r = write (sock, buf, len);
    if (r == -1) {
      perror ("write");
      return -1;
    }
    buf += r;
    len -= r;
  }

  return 0;
}

int
xread (int sock, void *v_buf, size_t len)
{
  int r;
  char *buf = v_buf;

  while (len > 0) {
    r = read (sock, buf, len);
    if (r == -1) {
      perror ("read");
      return -1;
    }
    if (r == 0) {
      fprintf (stderr, "read: unexpected end of file on fd %d\n", sock);
      return -1;
    }
    buf += r;
    len -= r;
  }

  return 0;
}

int
add_string_nodup (struct stringsbuf *sb, char *str)
{
  char **new_argv;

  if (sb->size >= sb->alloc) {
    sb->alloc += 64;
    new_argv = realloc (sb->argv, sb->alloc * sizeof (char *));
    if (new_argv == NULL) {
      reply_with_perror ("realloc");
      free (str);
      return -1;
    }
    sb->argv = new_argv;
  }

  sb->argv[sb->size] = str;
  sb->size++;

  return 0;
}

int
add_string (struct stringsbuf *sb, const char *str)
{
  char *new_str = NULL;

  if (str) {
    new_str = strdup (str);
    if (new_str == NULL) {
      reply_with_perror ("strdup");
      return -1;
    }
  }

  return add_string_nodup (sb, new_str);
}

int
add_sprintf (struct stringsbuf *sb, const char *fs, ...)
{
  va_list args;
  char *str;
  int r;

  va_start (args, fs);
  r = vasprintf (&str, fs, args);
  va_end (args);
  if (r == -1) {
    reply_with_perror ("vasprintf");
    return -1;
  }

  return add_string_nodup (sb, str);
}

int
end_stringsbuf (struct stringsbuf *sb)
{
  return add_string_nodup (sb, NULL);
}

void
free_stringsbuf (struct stringsbuf *sb)
{
  if (sb->argv != NULL)
    free_stringslen (sb->argv, sb->size);
}

/* Take the ownership of the strings of the strings buffer,
 * resetting it to a null buffer.
 */
char **
take_stringsbuf (struct stringsbuf *sb)
{
  DECLARE_STRINGSBUF (null);
  char **ret = sb->argv;
  *sb = null;
  return ret;
}

/**
 * Returns true if C<v> is a power of 2.
 *
 * Uses the algorithm described at
 * L<http://graphics.stanford.edu/~seander/bithacks.html#DetermineIfPowerOf2>
 */
int
is_power_of_2 (unsigned long v)
{
  return v && ((v & (v - 1)) == 0);
}

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcmp (*p1, *p2);
}

void
sort_strings (char **argv, size_t len)
{
  qsort (argv, len, sizeof (char *), compare);
}

void
free_stringslen (char **argv, size_t len)
{
  size_t i;

  if (!argv)
    return;

  for (i = 0; i < len; ++i)
    free (argv[i]);
  free (argv);
}

/**
 * Split an output string into a NULL-terminated list of lines,
 * wrapped into a stringsbuf.
 *
 * Typically this is used where we have run an external command
 * which has printed out a list of things, and we want to return
 * an actual list.
 *
 * The corner cases here are quite tricky.  Note in particular:
 *
 * =over 4
 *
 * =item C<"">
 *
 * returns C<[]>
 *
 * =item C<"\n">
 *
 * returns C<[""]>
 *
 * =item C<"a\nb">
 *
 * returns C<["a"; "b"]>
 *
 * =item C<"a\nb\n">
 *
 * returns C<["a"; "b"]>
 *
 * =item C<"a\nb\n\n">
 *
 * returns C<["a"; "b"; ""]>
 *
 * =back
 *
 * The original string is written over and destroyed by this function
 * (which is usually OK because it's the 'out' string from
 * C<command*()>).  You can free the original string, because
 * C<add_string()> strdups the strings.
 *
 * C<argv> in the C<struct stringsbuf> will be C<NULL> in case of errors.
 */
struct stringsbuf
split_lines_sb (char *str)
{
  DECLARE_STRINGSBUF (lines);
  DECLARE_STRINGSBUF (null);
  char *p, *pend;

  if (STREQ (str, "")) {
    /* No need to check the return value, as the stringsbuf will be
     * returned as it is anyway.
     */
    end_stringsbuf (&lines);
    return lines;
  }

  p = str;
  while (p) {
    /* Empty last line? */
    if (p[0] == '\0')
      break;

    pend = strchr (p, '\n');
    if (pend) {
      *pend = '\0';
      pend++;
    }

    if (add_string (&lines, p) == -1) {
      free_stringsbuf (&lines);
      return null;
    }

    p = pend;
  }

  if (end_stringsbuf (&lines) == -1) {
    free_stringsbuf (&lines);
    return null;
  }

  return lines;
}

char **
split_lines (char *str)
{
  struct stringsbuf sb = split_lines_sb (str);
  return take_stringsbuf (&sb);
}

char **
empty_list (void)
{
  DECLARE_STRINGSBUF (ret);

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return ret.argv;
}

/**
 * Filter a list of strings.  Returns a newly allocated list of only
 * the strings where C<p (str) == true>.
 *
 * B<Note> it does not copy the strings, be careful not to double-free
 * them.
 */
char **
filter_list (bool (*p) (const char *str), char **strs)
{
  DECLARE_STRINGSBUF (ret);
  size_t i;

  for (i = 0; strs[i] != NULL; ++i) {
    if (p (strs[i])) {
      if (add_string_nodup (&ret, strs[i]) == -1) {
        free (ret.argv);
        return NULL;
      }
    }
  }
  if (end_stringsbuf (&ret) == -1) {
    free (ret.argv);
    return NULL;
  }

  return take_stringsbuf (&ret);
}

/**
 * Skip leading and trailing whitespace, updating the original string
 * in-place.
 */
void
trim (char *str)
{
  size_t len = strlen (str);

  while (len > 0 && c_isspace (str[len-1])) {
    str[len-1] = '\0';
    len--;
  }

  const char *p = str;
  while (*p && c_isspace (*p)) {
    p++;
    len--;
  }

  memmove (str, p, len+1);
}

/**
 * Parse the mountable descriptor for a btrfs subvolume.  Don't call
 * this directly; it is only used from the stubs.
 *
 * A btrfs subvolume is given as:
 *
 *  btrfsvol:/dev/sda3/root
 *
 * where F</dev/sda3> is a block device containing a btrfs filesystem,
 * and root is the name of a subvolume on it. This function is passed
 * the string following C<"btrfsvol:">.
 *
 * On success, C<mountable-E<gt>device> and C<mountable-E<gt>volume>
 * must be freed by the caller.
 */
int
parse_btrfsvol (const char *desc_orig, mountable_t *mountable)
{
  CLEANUP_FREE char *desc = NULL;
  CLEANUP_FREE char *device = NULL;
  const char *volume = NULL;
  char *slash;
  struct stat statbuf;

  mountable->type = MOUNTABLE_BTRFSVOL;

  if (!STRPREFIX (desc_orig, "/dev/"))
    return -1;

  desc = strdup (desc_orig);
  if (desc == NULL) {
    perror ("strdup");
    return -1;
  }

  slash = desc + strlen ("/dev/") - 1;
  while ((slash = strchr (slash + 1, '/'))) {
    *slash = '\0';

    free (device);
    device = device_name_translation (desc);
    if (!device) {
      perror (desc);
      continue;
    }

    if (stat (device, &statbuf) == -1) {
      perror (device);
      return -1;
    }

    if (!S_ISDIR (statbuf.st_mode) &&
        !is_root_device_stat (&statbuf)) {
      volume = slash + 1;
      break;
    }

    *slash = '/';
  }

  if (!device) return -1;

  if (!volume) return -1;

  mountable->volume = strdup (volume);
  if (!mountable->volume) {
    perror ("strdup");
    return -1;
  }

  mountable->device = device;
  device = NULL; /* to stop CLEANUP_FREE from freeing it */

  return 0;
}

/**
 * Convert a C<mountable_t> back to its string representation
 *
 * This function can be used in an error path, so must not call
 * C<reply_with_error>.
 */
char *
mountable_to_string (const mountable_t *mountable)
{
  char *desc;

  switch (mountable->type) {
  case MOUNTABLE_DEVICE:
  case MOUNTABLE_PATH:
    return strdup (mountable->device);

  case MOUNTABLE_BTRFSVOL:
    if (asprintf (&desc, "btrfsvol:%s/%s",
		  mountable->device, mountable->volume) == -1)
      return NULL;
    return desc;

  default:
    return NULL;
  }
}

/**
 * Check program exists and is executable on C<$PATH>.
 */
int
prog_exists (const char *prog)
{
  const char *pathc = getenv ("PATH");
  if (!pathc)
    return 0;

  CLEANUP_FREE char *path = strdup (pathc);
  if (path == NULL) abort ();

  const char *elem;
  char *saveptr;

  elem = strtok_r (path, ":", &saveptr);
  while (elem) {
    CLEANUP_FREE char *testprog;

    if (asprintf (&testprog, "%s/%s", elem, prog) == -1) abort ();
    if (access (testprog, X_OK) == 0)
      return 1;

    elem = strtok_r (NULL, ":", &saveptr);
  }

  /* Not found. */
  return 0;
}

/**
 * Pass a template such as C<"/sysroot/XXXXXXXX.XXX">.  This updates
 * the template to contain a randomly named file.  Any C<'X'>
 * characters after the final C<'/'> in the template are replaced with
 * random characters.
 *
 * Notes: You should probably use an 8.3 path, so it's compatible with
 * all filesystems including basic FAT.  Also this only substitutes
 * lowercase ASCII letters and numbers, again for compatibility with
 * lowest common denominator filesystems.
 *
 * This doesn't create a file or check whether or not the file exists
 * (it would be extremely unlikely to exist as long as the RNG is
 * working).
 *
 * If there is an error, C<-1> is returned.
 */
int
random_name (char *template)
{
  int fd;
  unsigned char c;
  char *p;

  fd = open ("/dev/urandom", O_RDONLY|O_CLOEXEC);
  if (fd == -1)
    return -1;

  p = strrchr (template, '/');
  if (p == NULL)
    abort ();                   /* internal error - bad template */

  while (*p) {
    if (*p == 'X') {
      if (read (fd, &c, 1) != 1) {
        close (fd);
        return -1;
      }
      *p = "0123456789abcdefghijklmnopqrstuvwxyz"[c % 36];
    }

    p++;
  }

  close (fd);
  return 0;
}

/**
 * LVM and other commands aren't synchronous, especially when udev is
 * involved.  eg. You can create or remove some device, but the
 * C</dev> device node won't appear until some time later.  This means
 * that you get an error if you run one command followed by another.
 *
 * Use C<udevadm settle> after certain commands, but don't be too
 * fussed if it fails.
 */
void
udev_settle_file (const char *file)
{
  const size_t MAX_ARGS = 64;
  const char *argv[MAX_ARGS];
  CLEANUP_FREE char *err = NULL;
  size_t i = 0;
  int r;

  ADD_ARG (argv, i, "udevadm");
  if (verbose)
    ADD_ARG (argv, i, "--debug");

  ADD_ARG (argv, i, "settle");
  if (file) {
    ADD_ARG (argv, i, "-E");
    ADD_ARG (argv, i, file);
  }
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, argv);
  if (r == -1)
    fprintf (stderr, "udevadm settle: %s\n", err);
}

void
udev_settle (void)
{
  udev_settle_file (NULL);
}

char *
get_random_uuid (void)
{
  int r;
  char *out;
  CLEANUP_FREE char *err = NULL;

  r = command (&out, &err, "uuidgen", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  /* caller free */
  return out;

}

/**
 * Turn list C<excludes> into a temporary file, and return a string
 * containing the temporary file name.  Caller must unlink the file
 * and free the string.
 *
 * C<function> is the function that invoked this helper, and it is
 * used mainly for errors/debugging.
 */
char *
make_exclude_from_file (const char *function, char *const *excludes)
{
  size_t i;
  int fd;
  char template[] = "/tmp/excludesXXXXXX";
  char *ret;

  fd = mkstemp (template);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return NULL;
  }

  for (i = 0; excludes[i] != NULL; ++i) {
    if (strchr (excludes[i], '\n')) {
      reply_with_error ("%s: excludes file patterns cannot contain \\n character",
                        function);
      goto error;
    }

    if (xwrite (fd, excludes[i], strlen (excludes[i])) == -1 ||
        xwrite (fd, "\n", 1) == -1) {
      reply_with_perror ("write");
      goto error;
    }

    if (verbose)
      fprintf (stderr, "%s: adding excludes pattern '%s'\n",
               function, excludes[i]);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close");
    fd = -1;
    goto error;
  }
  fd = -1;

  ret = strdup (template);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    goto error;
  }

  return ret;

 error:
  if (fd >= 0)
    close (fd);
  unlink (template);
  return NULL;
}

void
cleanup_free_mountable (mountable_t *mountable)
{
  if (mountable) {
    free (mountable->device);
    free (mountable->volume);
  }
}

/**
 * Read whole file into dynamically allocated array.  If there is an
 * error, DON'T call reply_with_perror, just return NULL.  Returns a
 * C<\0>-terminated string.  C<size_r> can be specified to get the
 * size of the returned data.
 */
char *
read_whole_file (const char *filename, size_t *size_r)
{
  char *r = NULL;
  size_t alloc = 0, size = 0;
  int fd;

  fd = open (filename, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perror (filename);
    return NULL;
  }

  while (1) {
    alloc += 256;
    char *r2 = realloc (r, alloc);
    if (r2 == NULL) {
      perror ("realloc");
      free (r);
      close (fd);
      return NULL;
    }
    r = r2;

    /* The '- 1' in the size calculation ensures there is space below
     * to add \0 to the end of the input.
     */
    ssize_t n = read (fd, r + size, alloc - size - 1);
    if (n == -1) {
      fprintf (stderr, "read: %s: %m\n", filename);
      free (r);
      close (fd);
      return NULL;
    }
    if (n == 0)
      break;
    size += n;
  }

  if (close (fd) == -1) {
    fprintf (stderr, "close: %s: %m\n", filename);
    free (r);
    return NULL;
  }

  r[size] = '\0';
  if (size_r != NULL)
    *size_r = size;

  return r;
}
