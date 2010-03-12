/* libguestfs-supermin-helper reimplementation in C.
 * Copyright (C) 2009-2010 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/* This script builds the supermin appliance on the fly each
 * time the appliance runs.
 *
 * *NOTE*: This program is designed to be very short-lived, and so we
 * don't normally bother to free up any memory that we allocate.
 * That's not completely true - we free up stuff if it's obvious and
 * easy to free up, and ignore the rest.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <unistd.h>
#include <getopt.h>
#include <limits.h>
#include <fnmatch.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"
#include "filevercmp.h"
#include "fts_.h"
#include "full-write.h"
#include "hash.h"
#include "hash-pjw.h"
#include "xalloc.h"
#include "xvasprintf.h"

/* Directory containing candidate kernels.  We could make this
 * configurable at some point.
 */
#define KERNELDIR "/boot"
#define MODULESDIR "/lib/modules"

/* Buffer size used in copy operations throughout.  Large for
 * greatest efficiency.
 */
#define BUFFER_SIZE 65536

static struct timeval start_t;
static int verbose = 0;

static void print_timestamped_message (const char *fs, ...);
static const char *create_kernel (const char *hostcpu, const char *kernel);
static void create_appliance (const char *sourcedir, const char *hostcpu, const char *repo, const char *modpath, const char *initrd);

enum { HELP_OPTION = CHAR_MAX + 1 };

static const char *options = "vV";
static const struct option long_options[] = {
  { "help", 0, 0, HELP_OPTION },
  { "verbose", 0, 0, 'v' },
  { "version", 0, 0, 'V' },
  { 0, 0, 0, 0 }
};

static void
usage (const char *progname)
{
  printf ("%s: build the supermin appliance on the fly\n"
          "\n"
          "Usage:\n"
          "  %s [-options] sourcedir host_cpu repo kernel initrd\n"
          "  %s --help\n"
          "  %s --version\n"
          "\n"
          "This script is used by libguestfs to build the supermin appliance\n"
          "(kernel and initrd output files).  You should NOT need to run this\n"
          "program directly except if you are debugging tricky supermin\n"
          "appliance problems.\n"
          "\n"
          "NB: The kernel and initrd parameters are OUTPUT parameters.  If\n"
          "those files exist, they are overwritten by the output.\n"
          "\n"
          "Options:\n"
          "  --help\n"
          "       Display this help text and exit.\n"
          "  --verbose | -v\n"
          "       Enable verbose messages (give multiple times for more verbosity).\n"
          "  --version | -V\n"
          "       Display version number and exit.\n"
          "\n"
          "Typical usage when debugging supermin appliance problems:\n"
          "  %s -v /usr/lib*/guestfs x86_64 fedora-12 /tmp/kernel /tmp/initrd\n"
          "Note: This will OVERWRITE any existing files called /tmp/kernel\n"
          "and /tmp/initrd.\n",
          progname, progname, progname, progname, progname);
}

int
main (int argc, char *argv[])
{
  /* First thing: start the clock. */
  gettimeofday (&start_t, NULL);

  /* Command line arguments. */
  for (;;) {
    int c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case HELP_OPTION:
      usage (argv[0]);
      exit (EXIT_SUCCESS);

    case 'v':
      verbose++;
      break;

    case 'V':
      printf (PACKAGE_NAME " " PACKAGE_VERSION "\n");
      exit (EXIT_SUCCESS);

    default:
      usage (argv[0]);
      exit (EXIT_FAILURE);
    }
  }

  if (argc - optind != 5) {
    usage (argv[0]);
    exit (EXIT_FAILURE);
  }

  const char *sourcedir = argv[optind];

  /* Host CPU and repo constants passed from the library (see:
   * https://bugzilla.redhat.com/show_bug.cgi?id=558593).
   */
  const char *hostcpu = argv[optind+1];
  const char *repo = argv[optind+2];

  /* Output files. */
  const char *kernel = argv[optind+3];
  const char *initrd = argv[optind+4];

  if (verbose)
    print_timestamped_message ("sourcedir = %s, "
                               "host_cpu = %s, "
                               "repo = %s, "
                               "kernel = %s, "
                               "initrd = %s",
                               sourcedir, hostcpu, repo, kernel, initrd);

  /* Remove the output files if they exist. */
  unlink (kernel);
  unlink (initrd);

  /* Create kernel output file. */
  const char *modpath;
  modpath = create_kernel (hostcpu, kernel);

  if (verbose)
    print_timestamped_message ("finished creating kernel");

  /* Create the appliance. */
  create_appliance (sourcedir, hostcpu, repo, modpath, initrd);

  if (verbose)
    print_timestamped_message ("finished creating appliance");

  exit (EXIT_SUCCESS);
}

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
static int64_t
timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

static void
print_timestamped_message (const char *fs, ...)
{
  struct timeval tv;
  gettimeofday (&tv, NULL);

  va_list args;
  char *msg;
  int err;

  va_start (args, fs);
  err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  fprintf (stderr, "supermin helper [%05" PRIi64 "ms] %s\n",
           timeval_diff (&start_t, &tv), msg);

  free (msg);
}

static char **read_dir (const char *dir);
static char **filter_fnmatch (char **strings, const char *patt, int flags);
static char **filter_notmatching_substring (char **strings, const char *sub);
static void sort (char **strings, int (*compare) (const void *, const void *));
static int isdir (const char *path);

static int
reverse_filevercmp (const void *p1, const void *p2)
{
  const char *s1 = * (char * const *) p1;
  const char *s2 = * (char * const *) p2;

  /* Note, arguments are reversed to achieve a reverse sort. */
  return filevercmp (s2, s1);
}

/* Create the kernel.  This chooses an appropriate kernel and makes a
 * symlink to it.
 *
 * Look for the most recent kernel named vmlinuz-*.<arch>* which has a
 * corresponding directory in /lib/modules/. If the architecture is
 * x86, look for any x86 kernel.
 *
 * RHEL 5 didn't append the arch to the kernel name, so look for
 * kernels without arch second.
 *
 * If no suitable kernel can be found, exit with an error.
 *
 * This function returns the module path (ie. /lib/modules/<version>).
 */
static const char *
create_kernel (const char *hostcpu, const char *kernel)
{
  char **all_files = read_dir (KERNELDIR);

  /* In original: ls -1dvr /boot/vmlinuz-*.$arch* 2>/dev/null | grep -v xen */
  const char *patt;
  if (hostcpu[0] == 'i' && hostcpu[2] == '8' && hostcpu[3] == '6' &&
      hostcpu[4] == '\0')
    patt = "vmlinuz-*.i?86*";
  else
    patt = xasprintf ("vmlinuz-*.%s*", hostcpu);

  char **candidates;
  candidates = filter_fnmatch (all_files, patt, FNM_NOESCAPE);
  candidates = filter_notmatching_substring (candidates, "xen");

  if (candidates[0] == NULL) {
    /* In original: ls -1dvr /boot/vmlinuz-* 2>/dev/null | grep -v xen */
    patt = "vmlinuz-*";
    candidates = filter_fnmatch (all_files, patt, FNM_NOESCAPE);
    candidates = filter_notmatching_substring (candidates, "xen");

    if (candidates[0] == NULL)
      goto no_kernels;
  }

  sort (candidates, reverse_filevercmp);

  /* Choose the first candidate which has a corresponding /lib/modules
   * directory.
   */
  int i;
  for (i = 0; candidates[i] != NULL; ++i) {
    if (verbose >= 2)
      fprintf (stderr, "candidate kernel: " KERNELDIR "/%s\n", candidates[i]);

    /* Ignore "vmlinuz-" at the beginning of the kernel name. */
    const char *version = &candidates[i][8];

    /* /lib/modules/<version> */
    char *modpath = xasprintf (MODULESDIR "/%s", version);

    if (verbose >= 2)
      fprintf (stderr, "checking modpath %s is a directory\n", modpath);

    if (isdir (modpath)) {
      if (verbose >= 2)
        fprintf (stderr, "picked %s because modpath %s exists\n",
                 candidates[i], modpath);

      char *tmp = xasprintf (KERNELDIR "/%s", candidates[i]);

      if (verbose >= 2)
        fprintf (stderr, "creating symlink %s -> %s\n", kernel, tmp);

      if (symlink (tmp, kernel) == -1)
        error (EXIT_FAILURE, errno, "symlink kernel");

      free (tmp);

      return modpath;
    }
  }

  /* Print more diagnostics here than the old script did. */
 no_kernels:
  fprintf (stderr,
           "libguestfs-supermin-helper: failed to find a suitable kernel.\n"
           "I looked for kernels in " KERNELDIR " and modules in " MODULESDIR
           ".\n"
           "If this is a Xen guest, and you only have Xen domU kernels\n"
           "installed, try installing a fullvirt kernel (only for\n"
           "libguestfs use, you shouldn't boot the Xen guest with it).\n");
  exit (EXIT_FAILURE);
}

static void write_kernel_modules (const char *sourcedir, const char *modpath);
static void write_hostfiles (const char *sourcedir, const char *hostcpu, const char *repo);
static void write_to_fd (const void *buffer, size_t len);
static void write_file_to_fd (const char *filename);
static void write_file_len_to_fd (const char *filename, size_t len);
static void write_padding (size_t len);
static char **load_file (const char *filename);
static void cpio_append_fts_entry (FTSENT *entry);
static void cpio_append_stat (const char *filename, struct stat *);
static void cpio_append (const char *filename);
static void cpio_append_trailer (void);

static int out_fd = -1;
static off_t out_offset = 0;

/* Create the appliance.
 *
 * The initrd consists of these components concatenated together:
 *
 * (1) The base skeleton appliance that we constructed at build time.
 *     name = initramfs.$repo.$host_cpu.supermin.img
 *     format = plain cpio
 * (2) The modules from modpath which are on the module whitelist.
 *     format = plain cpio
 * (3) The host files which match wildcards in *.supermin.hostfiles.
 *     format = plain cpio
 *
 * The original shell scripted used the external cpio program to
 * create parts (2) and (3), but we have decided it's going to be
 * faster if we just write out the data outselves.  The reasons are
 * that external cpio is slow (particularly when used with SELinux
 * because it does 512 byte reads), and the format that we're writing
 * is narrow and well understood, because we only care that the Linux
 * kernel can read it.
 */
static void
create_appliance (const char *sourcedir,
                  const char *hostcpu, const char *repo,
                  const char *modpath,
                  const char *initrd)
{
  out_fd = open (initrd, O_WRONLY | O_CREAT | O_TRUNC | O_NOCTTY, 0644);
  if (out_fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", initrd);
  out_offset = 0;

  /* Copy the base skeleton appliance (1). */
  char *tmp = xasprintf ("%s/initramfs.%s.%s.supermin.img",
                         sourcedir, repo, hostcpu);
  write_file_to_fd (tmp);
  free (tmp);

  /* Kernel modules (2). */
  write_kernel_modules (sourcedir, modpath);

  /* Copy hostfiles (3). */
  write_hostfiles (sourcedir, hostcpu, repo);

  cpio_append_trailer ();

  /* Finish off and close output file. */
  if (close (out_fd) == -1)
    error (EXIT_FAILURE, errno, "close: %s", initrd);
}

/* Copy kernel modules.
 *
 * Find every file under modpath.
 *
 * Exclude all *.ko files, *except* ones which match names in
 * the whitelist (which may contain wildcards).  Include all
 * other files.
 *
 * Add chosen files to the output.
 */
static void
write_kernel_modules (const char *sourcedir, const char *modpath)
{
  char *tmp = xasprintf ("%s/kmod.whitelist", sourcedir);
  char **whitelist = load_file (tmp);
  free (tmp);

  char *paths[2] = { (char *) modpath, NULL };
  FTS *fts = fts_open (paths, FTS_COMFOLLOW|FTS_PHYSICAL, NULL);
  if (fts == NULL)
    error (EXIT_FAILURE, errno, "write_kernel_modules: fts_open: %s", modpath);

  for (;;) {
    errno = 0;
    FTSENT *entry = fts_read (fts);
    if (entry == NULL && errno != 0)
      error (EXIT_FAILURE, errno, "write_kernel_modules: fts_read: %s", modpath);
    if (entry == NULL)
      break;

    /* Ignore directories being visited in post-order. */
    if (entry->fts_info & FTS_DP)
      continue;

    /* Is it a *.ko file? */
    if (entry->fts_namelen >= 3 &&
        entry->fts_name[entry->fts_namelen-3] == '.' &&
        entry->fts_name[entry->fts_namelen-2] == 'k' &&
        entry->fts_name[entry->fts_namelen-1] == 'o') {
      /* Is it a *.ko file which is on the whitelist? */
      size_t j;
      for (j = 0; whitelist[j] != NULL; ++j) {
        int r;
        r = fnmatch (whitelist[j], entry->fts_name, 0);
        if (r == 0) {
          /* It's on the whitelist, so include it. */
          if (verbose >= 2)
            fprintf (stderr, "including kernel module %s (matches whitelist entry %s)\n",
                     entry->fts_name, whitelist[j]);
          cpio_append_fts_entry (entry);
          break;
        } else if (r != FNM_NOMATCH)
          error (EXIT_FAILURE, 0, "internal error: fnmatch ('%s', '%s', %d) returned unexpected non-zero value %d\n",
                 whitelist[j], entry->fts_name, 0, r);
      } /* for (j) */
    } else
      /* It's some other sort of file, or a directory, always include. */
      cpio_append_fts_entry (entry);
  }

  if (fts_close (fts) == -1)
    error (EXIT_FAILURE, errno, "write_kernel_modules: fts_close: %s", modpath);
}

/* Copy the host files.
 *
 * Read the list of entries in *.supermin.hostfiles (which may contain
 * wildcards).  Look them up in the filesystem, and add those files
 * that exist.  Ignore any files that don't exist or are not readable.
 */
static void
write_hostfiles (const char *sourcedir, const char *hostcpu, const char *repo)
{
  char *tmp = xasprintf ("%s/initramfs.%s.%s.supermin.hostfiles",
                         sourcedir, repo, hostcpu);
  char **hostfiles = load_file (tmp);
  free (tmp);

  /* Hostfiles list can contain "." before each path - ignore it.
   * It also contains each directory name before we enter it.  But
   * we don't read that until we see a wildcard for that directory.
   */
  size_t i, j;
  for (i = 0; hostfiles[i] != NULL; ++i) {
    char *hostfile = hostfiles[i];
    if (hostfile[0] == '.')
      hostfile++;

    struct stat statbuf;

    /* Is it a wildcard? */
    if (strchr (hostfile, '*') || strchr (hostfile, '?')) {
      char *dirname = xstrdup (hostfile);
      char *patt = strrchr (dirname, '/');
      assert (patt);
      *patt++ = '\0';

      char **files = read_dir (dirname);
      files = filter_fnmatch (files, patt, FNM_NOESCAPE);

      /* Add matching files. */
      for (j = 0; files[j] != NULL; ++j) {
        tmp = xasprintf ("%s/%s", dirname, files[j]);

        if (verbose >= 2)
          fprintf (stderr, "including host file %s (matches %s)\n", tmp, patt);

        cpio_append (tmp);

        free (tmp);
      }
    }
    /* Else does this file/directory/whatever exist? */
    else if (lstat (hostfile, &statbuf) == 0) {
      if (verbose >= 2)
        fprintf (stderr, "including host file %s (directly referenced)\n",
                 hostfile);

      cpio_append_stat (hostfile, &statbuf);
    } /* Ignore files that don't exist. */
  }
}

/*----------*/
/* Helper functions. */

static void
add_string (char ***argv, size_t *n_used, size_t *n_alloc, const char *str)
{
  char **new_argv;
  char *new_str;

  if (*n_used >= *n_alloc)
    *argv = x2nrealloc (*argv, n_alloc, sizeof (char *));

  if (str)
    new_str = xstrdup (str);
  else
    new_str = NULL;

  (*argv)[*n_used] = new_str;

  (*n_used)++;
}

static size_t
count_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;
  return argc;
}

struct dir_cache {
  char *path;
  char **files;
};

static size_t
dir_cache_hash (void const *x, size_t table_size)
{
  struct dir_cache const *p = x;
  return hash_pjw (p->path, table_size);
}

static bool
dir_cache_compare (void const *x, void const *y)
{
  struct dir_cache const *p = x;
  struct dir_cache const *q = y;
  return strcmp (p->path, q->path) == 0;
}

/* Read a directory into a list of strings.
 *
 * Previously looked up directories are cached and returned quickly,
 * saving some considerable amount of time compared to reading the
 * directory over again.  However this means you really must not
 * alter the array of strings that are returned.
 *
 * Returns an empty list if the directory cannot be opened.
 */
static char **
read_dir (const char *name)
{
  static Hash_table *ht = NULL;

  if (!ht)
    ht = hash_initialize (1024, NULL, dir_cache_hash, dir_cache_compare, NULL);

  struct dir_cache key = { .path = (char *) name };
  struct dir_cache *p = hash_lookup (ht, &key);
  if (p)
    return p->files;

  char **files = NULL;
  size_t n_used = 0, n_alloc = 0;

  DIR *dir = opendir (name);
  if (!dir) {
    /* If it fails to open, that's OK, skip to the end. */
    /*perror (name);*/
    goto done;
  }

  for (;;) {
    errno = 0;
    struct dirent *d = readdir (dir);
    if (d == NULL) {
      if (errno != 0)
        /* But if it fails here, after opening and potentially reading
         * part of the directory, that's a proper failure - inform the
         * user and exit.
         */
        error (EXIT_FAILURE, errno, "%s", name);
      break;
    }

    add_string (&files, &n_used, &n_alloc, d->d_name);
  }

  if (closedir (dir) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", name);

 done:
  /* NULL-terminate the array. */
  add_string (&files, &n_used, &n_alloc, NULL);

  /* Add it to the hash for next time. */
  p = xmalloc (sizeof *p);
  p->path = (char *) name;
  p->files = files;
  p = hash_insert (ht, p);
  assert (p != NULL);

  return files;
}

/* Filter a list of strings and return only those matching the wildcard. */
static char **
filter_fnmatch (char **strings, const char *patt, int flags)
{
  char **out = NULL;
  size_t n_used = 0, n_alloc = 0;

  int i, r;
  for (i = 0; strings[i] != NULL; ++i) {
    r = fnmatch (patt, strings[i], flags);
    if (r == 0)
      add_string (&out, &n_used, &n_alloc, strings[i]);
    else if (r != FNM_NOMATCH)
      error (EXIT_FAILURE, 0, "internal error: fnmatch ('%s', '%s', %d) returned unexpected non-zero value %d\n",
             patt, strings[i], flags, r);
  }

  add_string (&out, &n_used, &n_alloc, NULL);
  return out;
}

/* Filter a list of strings and return only those which DON'T contain sub. */
static char **
filter_notmatching_substring (char **strings, const char *sub)
{
  char **out = NULL;
  size_t n_used = 0, n_alloc = 0;

  int i;
  for (i = 0; strings[i] != NULL; ++i) {
    if (strstr (strings[i], sub) == NULL)
      add_string (&out, &n_used, &n_alloc, strings[i]);
  }

  add_string (&out, &n_used, &n_alloc, NULL);
  return out;
}

/* Sort a list of strings, in place, with the comparison function supplied. */
static void
sort (char **strings, int (*compare) (const void *, const void *))
{
  qsort (strings, count_strings (strings), sizeof (char *), compare);
}

/* Return true iff path exists and is a directory.  This version
 * follows symlinks.
 */
static int
isdir (const char *path)
{
  struct stat statbuf;

  if (stat (path, &statbuf) == -1)
    return 0;

  return S_ISDIR (statbuf.st_mode);
}

/* Copy contents of buffer to out_fd and keep out_offset correct. */
static void
write_to_fd (const void *buffer, size_t len)
{
  if (full_write (out_fd, buffer, len) != len)
    error (EXIT_FAILURE, errno, "write");
  out_offset += len;
}

/* Copy contents of file to out_fd. */
static void
write_file_to_fd (const char *filename)
{
  char buffer[BUFFER_SIZE];
  int fd2;
  ssize_t r;

  if (verbose >= 2)
    fprintf (stderr, "write_file_to_fd %s -> %d\n", filename, out_fd);

  fd2 = open (filename, O_RDONLY);
  if (fd2 == -1)
    error (EXIT_FAILURE, errno, "open: %s", filename);
  for (;;) {
    r = read (fd2, buffer, sizeof buffer);
    if (r == 0)
      break;
    if (r == -1) {
      if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
        continue;
      error (EXIT_FAILURE, errno, "read: %s", filename);
    }
    write_to_fd (buffer, r);
  }

  if (close (fd2) == -1)
    error (EXIT_FAILURE, errno, "close: %s", filename);
}

/* Copy file of given length to output, and fail if the file has
 * changed size.
 */
static void
write_file_len_to_fd (const char *filename, size_t len)
{
  char buffer[BUFFER_SIZE];
  size_t count = 0;

  if (verbose >= 2)
    fprintf (stderr, "write_file_to_fd %s -> %d\n", filename, out_fd);

  int fd2 = open (filename, O_RDONLY);
  if (fd2 == -1)
    error (EXIT_FAILURE, errno, "open: %s", filename);
  for (;;) {
    ssize_t r = read (fd2, buffer, sizeof buffer);
    if (r == 0)
      break;
    if (r == -1) {
      if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
        continue;
      error (EXIT_FAILURE, errno, "read: %s", filename);
    }
    write_to_fd (buffer, r);
    count += r;
    if (count > len)
      error (EXIT_FAILURE, 0, "write_file_len_to_fd: %s: file has increased in size\n", filename);
  }

  if (close (fd2) == -1)
    error (EXIT_FAILURE, errno, "close: %s", filename);

  if (count != len)
    error (EXIT_FAILURE, 0, "libguestfs-supermin-helper: write_file_len_to_fd: %s: file has changed size\n", filename);
}

/* Load in a file, returning a list of lines. */
static char **
load_file (const char *filename)
{
  char **lines = 0;
  size_t n_used = 0, n_alloc = 0;

  FILE *fp;
  fp = fopen (filename, "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "fopen: %s", filename);

  char line[4096];
  while (fgets (line, sizeof line, fp)) {
    size_t len = strlen (line);
    if (len > 0 && line[len-1] == '\n')
      line[len-1] = '\0';
    add_string (&lines, &n_used, &n_alloc, line);
  }

  add_string (&lines, &n_used, &n_alloc, NULL);
  return lines;
}

/* Append the file pointed to by FTSENT to the cpio output. */
static void
cpio_append_fts_entry (FTSENT *entry)
{
  if (entry->fts_info & FTS_NS || entry->fts_info & FTS_NSOK)
    cpio_append (entry->fts_path);
  else
    cpio_append_stat (entry->fts_path, entry->fts_statp);
}

/* Append the file named 'filename' to the cpio output. */
static void
cpio_append (const char *filename)
{
  struct stat statbuf;

  if (lstat (filename, &statbuf) == -1)
    error (EXIT_FAILURE, errno, "lstat: %s", filename);
  cpio_append_stat (filename, &statbuf);
}

/* Append the file to the cpio output. */
#define PADDING(len) ((((len) + 3) & ~3) - (len))

#define CPIO_HEADER_LEN (6 + 13*8)

static void
cpio_append_stat (const char *filename, struct stat *statbuf)
{
  const char *orig_filename = filename;

  if (*filename == '/')
    filename++;
  if (*filename == '\0')
    filename = ".";

  if (verbose >= 2)
    fprintf (stderr, "cpio_append_stat %s 0%o -> %d\n",
             orig_filename, statbuf->st_mode, out_fd);

  /* Regular files and symlinks are the only ones that have a "body"
   * in this cpio entry.
   */
  int has_body = S_ISREG (statbuf->st_mode) || S_ISLNK (statbuf->st_mode);

  size_t len = strlen (filename) + 1;

  char header[CPIO_HEADER_LEN + 1];
  snprintf (header, sizeof header,
            "070701"            /* magic */
            "%08X"              /* inode */
            "%08X"              /* mode */
            "%08X" "%08X"       /* uid, gid */
            "%08X"              /* nlink */
            "%08X"              /* mtime */
            "%08X"              /* file length */
            "%08X" "%08X"       /* device holding file major, minor */
            "%08X" "%08X"       /* for specials, device major, minor */
            "%08X"              /* name length (including \0 byte) */
            "%08X",             /* checksum (not used by the kernel) */
            (unsigned) statbuf->st_ino, statbuf->st_mode,
            statbuf->st_uid, statbuf->st_gid,
            (unsigned) statbuf->st_nlink, (unsigned) statbuf->st_mtime,
            has_body ? (unsigned) statbuf->st_size : 0,
            major (statbuf->st_dev), minor (statbuf->st_dev),
            major (statbuf->st_rdev), minor (statbuf->st_rdev),
            (unsigned) len, 0);

  /* Write the header. */
  write_to_fd (header, CPIO_HEADER_LEN);

  /* Follow with the filename, and pad it. */
  write_to_fd (filename, len);
  size_t padding_len = PADDING (CPIO_HEADER_LEN + len);
  write_padding (padding_len);

  /* Follow with the file or symlink content, and pad it. */
  if (has_body) {
    if (S_ISREG (statbuf->st_mode))
      write_file_len_to_fd (orig_filename, statbuf->st_size);
    else if (S_ISLNK (statbuf->st_mode)) {
      char tmp[PATH_MAX];
      if (readlink (orig_filename, tmp, sizeof tmp) == -1)
        error (EXIT_FAILURE, errno, "readlink: %s", orig_filename);
      write_to_fd (tmp, statbuf->st_size);
    }

    padding_len = PADDING (statbuf->st_size);
    write_padding (padding_len);
  }
}

/* CPIO voodoo. */
static void
cpio_append_trailer (void)
{
  struct stat statbuf;
  memset (&statbuf, 0, sizeof statbuf);
  statbuf.st_nlink = 1;
  cpio_append_stat ("TRAILER!!!", &statbuf);

  /* CPIO seems to pad up to the next block boundary, ie. up to
   * the next 512 bytes.
   */
  write_padding (((out_offset + 511) & ~511) - out_offset);
  assert ((out_offset & 511) == 0);
}

/* Write 'len' bytes of zeroes out. */
static void
write_padding (size_t len)
{
  static const char buffer[512] = { 0 };

  while (len > 0) {
    size_t n = len < sizeof buffer ? len : sizeof buffer;
    write_to_fd (buffer, n);
    len -= n;
  }
}
