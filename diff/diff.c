/* virt-diff
 * Copyright (C) 2013 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <time.h>
#include <libintl.h>
#include <sys/wait.h>

#include "c-ctype.h"
#include "human.h"

#include "guestfs.h"

#include "options.h"
#include "visit.h"

/* Internal tree structure built for each guest. */
struct tree;
static struct tree *visit_guest (guestfs_h *g);
static int diff_guests (struct tree *t1, struct tree *t2);
static void free_tree (struct tree *);

/* Libguestfs handles for two source guests. */
guestfs_h *g, *g2;

int read_only = 1;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 1;

static int atime = 0;
static int csv = 0;
static int dir_links = 0;
static int dir_times = 0;
static int human = 0;
static int enable_extra_stats = 0;
static int enable_times = 0;
static int enable_uids = 0;
static int enable_xattrs = 0;
static int time_t_output = 0;
static int time_relative = 0; /* 1 = seconds, 2 = days */
static const char *checksum = NULL;

static time_t now;

static void output_start_line (void);
static void output_end_line (void);
static void output_flush (void);
static void output_int64 (int64_t);
static void output_int64_dev (int64_t);
static void output_int64_perms (int64_t);
static void output_int64_size (int64_t);
static void output_int64_time (int64_t secs, int64_t nsecs);
static void output_int64_uid (int64_t);
static void output_string (const char *);
static void output_string_link (const char *);
static void output_binary (const char *, size_t len);

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             guestfs_int_program_name);
  else {
    printf (_("%s: list differences between virtual machines\n"
              "Copyright (C) 2010-2016 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] -d domain1 -D domain2\n"
              "  %s [--options] -a disk1.img -A disk2.img [-a|-A ...]\n"
              "Options:\n"
              "  -a|--add image       Add image from first guest\n"
              "  --all                Same as: --extra-stats --times --uids --xattrs\n"
              "  --atime              Don't ignore access time changes\n"
              "  -A image             Add image from second guest\n"
              "  --checksum[=...]     Use checksum of file content\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  --csv                Comma-Separated Values output\n"
              "  --dir-links          Don't ignore directory nlink changes\n"
              "  --dir-times          Don't ignore directory time changes\n"
              "  -d|--domain guest    Add disks from first libvirt guest\n"
              "  -D guest             Add disks from second libvirt guest\n"
              "  --echo-keys          Don't turn off echo for passphrases\n"
              "  --extra-stats        Display extra stats\n"
              "  --format[=raw|..]    Force disk format for -a or -A option\n"
              "  --help               Display brief help\n"
              "  -h|--human-readable  Human-readable sizes in output\n"
              "  --keys-from-stdin    Read passphrases from stdin\n"
              "  --times              Display file times\n"
              "  --time-days          Display file times as days before now\n"
              "  --time-relative      Display file times as seconds before now\n"
              "  --time-t             Display file times as time_t's\n"
              "  --uids               Display UID, GID\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -x                   Trace libguestfs API calls\n"
              "  --xattrs             Display extended attributes\n"
              "For more information, see the manpage %s(1).\n"),
            guestfs_int_program_name, guestfs_int_program_name,
            guestfs_int_program_name, guestfs_int_program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  /* Current time for --time-days, --time-relative output. */
  time (&now);

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:A:c:d:D:hvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "all", 0, 0, 0 },
    { "atime", 0, 0, 0 },
    { "checksum", 2, 0, 0 },
    { "checksums", 2, 0, 0 },
    { "csv", 0, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "dir-link", 0, 0, 0 },
    { "dir-links", 0, 0, 0 },
    { "dir-nlink", 0, 0, 0 },
    { "dir-nlinks", 0, 0, 0 },
    { "dir-time", 0, 0, 0 },
    { "dir-times", 0, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "extra-stat", 0, 0, 0 },
    { "extra-stats", 0, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "human-readable", 0, 0, 'h' },
    { "long-options", 0, 0, 0 },
    { "keys-from-stdin", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "time", 0, 0, 0 },
    { "times", 0, 0, 0 },
    { "time-days", 0, 0, 0 },
    { "time-relative", 0, 0, 0 },
    { "time-t", 0, 0, 0 },
    { "uid", 0, 0, 0 },
    { "uids", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { "xattr", 0, 0, 0 },
    { "xattrs", 0, 0, 0 },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;      /* First guest. */
  struct drv *drvs2 = NULL;     /* Second guest. */
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int option_index;
  struct tree *tree1, *tree2;

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  g2 = guestfs_create ();
  if (g2 == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "all")) {
        enable_extra_stats = enable_times = enable_uids = enable_xattrs = 1;
      } else if (STREQ (long_options[option_index].name, "atime")) {
        atime = 1;
      } else if (STREQ (long_options[option_index].name, "csv")) {
        csv = 1;
      } else if (STREQ (long_options[option_index].name, "checksum") ||
                 STREQ (long_options[option_index].name, "checksums")) {
        if (!optarg || STREQ (optarg, ""))
          checksum = "md5";
        else
          checksum = optarg;
      } else if (STREQ (long_options[option_index].name, "dir-link") ||
                 STREQ (long_options[option_index].name, "dir-links") ||
                 STREQ (long_options[option_index].name, "dir-nlink") ||
                 STREQ (long_options[option_index].name, "dir-nlinks")) {
        dir_links = 1;
      } else if (STREQ (long_options[option_index].name, "dir-time") ||
                 STREQ (long_options[option_index].name, "dir-times")) {
        dir_times = 1;
      } else if (STREQ (long_options[option_index].name, "extra-stat") ||
                 STREQ (long_options[option_index].name, "extra-stats")) {
        enable_extra_stats = 1;
      } else if (STREQ (long_options[option_index].name, "time") ||
                 STREQ (long_options[option_index].name, "times")) {
        enable_times = 1;
      } else if (STREQ (long_options[option_index].name, "time-t")) {
        enable_times = 1;
        time_t_output = 1;
      } else if (STREQ (long_options[option_index].name, "time-relative")) {
        enable_times = 1;
        time_t_output = 1;
        time_relative = 1;
      } else if (STREQ (long_options[option_index].name, "time-days")) {
        enable_times = 1;
        time_t_output = 1;
        time_relative = 2;
      } else if (STREQ (long_options[option_index].name, "uid") ||
                 STREQ (long_options[option_index].name, "uids")) {
        enable_uids = 1;
      } else if (STREQ (long_options[option_index].name, "xattr") ||
                 STREQ (long_options[option_index].name, "xattrs")) {
        enable_xattrs = 1;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 guestfs_int_program_name,
                 long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'a':
      OPTION_a;
      break;

    case 'A':
      OPTION_A;
      break;

    case 'c':
      OPTION_c;
      break;

    case 'd':
      OPTION_d;
      break;

    case 'D':
      OPTION_D;
      break;

    case 'h':
      human = 1;
      break;

    case 'v':
      /* OPTION_v; */
      verbose++;
      guestfs_set_verbose (g, verbose);
      guestfs_set_verbose (g2, verbose);
      break;

    case 'V':
      OPTION_V;
      break;

    case 'x':
      /* OPTION_x; */
      guestfs_set_trace (g, 1);
      guestfs_set_trace (g2, 1);
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a or -d option.\n"),
             guestfs_int_program_name);
    usage (EXIT_FAILURE);
  }
  if (drvs2 == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -A or -D option.\n"),
             guestfs_int_program_name);
    usage (EXIT_FAILURE);
  }

  /* CSV && human is unsafe because spreadsheets fail to parse these
   * fields correctly.  (RHBZ#600977).
   */
  if (human && csv) {
    fprintf (stderr, _("%s: you cannot use -h and --csv options together.\n"),
             guestfs_int_program_name);
    exit (EXIT_FAILURE);
  }

  if (optind != argc) {
    fprintf (stderr, _("%s: extra arguments on the command line\n"),
             guestfs_int_program_name);
    usage (EXIT_FAILURE);
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 1);
  assert (live == 0);

  CHECK_OPTION_format_consumed;

  unsigned errors = 0;

  /* Mount up first guest. */
  add_drives (drvs, 'a');

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  inspect_mount ();

  if ((tree1 = visit_guest (g)) == NULL)
    errors++;

  /* Mount up second guest. */
  add_drives_handle (g2, drvs2, 'a');

  if (guestfs_launch (g2) == -1)
    exit (EXIT_FAILURE);

  inspect_mount_handle (g2);

  if ((tree2 = visit_guest (g2)) == NULL)
    errors++;

  if (errors == 0) {
    if (diff_guests (tree1, tree2) == -1)
      errors++;
  }

  free_tree (tree1);
  free_tree (tree2);

  free_drives (drvs);
  free_drives (drvs2);

  guestfs_close (g);
  guestfs_close (g2);

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

struct tree {
  /* We store the handle here in case we need to go and dig into
   * the disk to get file content.
   */
  guestfs_h *g;

  /* List of files found, sorted by path. */
  struct file *files;
  size_t nr_files, allocated;
};

struct file {
  char *path;
  struct guestfs_statns *stat;
  struct guestfs_xattr_list *xattrs;
  char *csum;                  /* Checksum. If NULL, use file times and size. */
};

static void
free_tree (struct tree *t)
{
  size_t i;

  for (i = 0; i < t->nr_files; ++i) {
    free (t->files[i].path);
    guestfs_free_statns (t->files[i].stat);
    guestfs_free_xattr_list (t->files[i].xattrs);
    free (t->files[i].csum);
  }

  free (t->files);

  free (t);
}

static int visit_entry (const char *dir, const char *name, const struct guestfs_statns *stat, const struct guestfs_xattr_list *xattrs, void *vt);

static struct tree *
visit_guest (guestfs_h *g)
{
  struct tree *t = malloc (sizeof *t);

  if (t == NULL) {
    perror ("malloc");
    return NULL;
  }

  t->g = g;
  t->files = NULL;
  t->nr_files = t->allocated = 0;

  if (visit (g, "/", visit_entry, t) == -1) {
    free_tree (t);
    return NULL;
  }

  if (verbose)
    fprintf (stderr, "read %zu entries from guest\n", t->nr_files);

  return t;
}

/* Visit each directory/file/etc entry in the tree.  This just stores
 * the data in the tree.  Note we don't store file content, but we
 * keep the guestfs handle open so we can pull that out later if we
 * need to.
 */
static int
visit_entry (const char *dir, const char *name,
             const struct guestfs_statns *stat_orig,
             const struct guestfs_xattr_list *xattrs_orig,
             void *vt)
{
  struct tree *t = vt;
  char *path = NULL, *csum = NULL;
  struct guestfs_statns *stat = NULL;
  struct guestfs_xattr_list *xattrs = NULL;
  size_t i;

  path = full_path (dir, name);

  /* Copy the stats and xattrs because the visit function will
   * free them after we return.
   */
  stat = guestfs_copy_statns (stat_orig);
  if (stat == NULL) {
    perror ("guestfs_copy_stat");
    goto error;
  }
  xattrs = guestfs_copy_xattr_list (xattrs_orig);
  if (xattrs == NULL) {
    perror ("guestfs_copy_xattr_list");
    goto error;
  }

  if (checksum && is_reg (stat->st_mode)) {
    csum = guestfs_checksum (t->g, checksum, path);
    if (!csum)
      goto error;
  }

  /* If --atime option was NOT passed, flatten the atime field. */
  if (!atime)
    stat->st_atime_sec = stat->st_atime_nsec = 0;

  /* If --dir-links option was NOT passed, flatten nlink field in
   * directories.
   */
  if (!dir_links && is_dir (stat->st_mode))
    stat->st_nlink = 0;

  /* If --dir-times option was NOT passed, flatten time fields in
   * directories.
   */
  if (!dir_times && is_dir (stat->st_mode))
    stat->st_atime_sec = stat->st_mtime_sec = stat->st_ctime_sec =
      stat->st_atime_nsec = stat->st_mtime_nsec = stat->st_ctime_nsec = 0;

  /* Add the pathname and stats to the list. */
  i = t->nr_files++;
  if (i >= t->allocated) {
    struct file *old_files = t->files;
    size_t old_allocated = t->allocated;

    /* Number of entries in an F15 guest was 111524, and in a
     * Windows guest was 10709.
     */
    if (old_allocated == 0)
      t->allocated = 1024;
    else
      t->allocated = old_allocated * 2;

    t->files = realloc (old_files, t->allocated * sizeof (struct file));
    if (t->files == NULL) {
      perror ("realloc");
      t->files = old_files;
      t->allocated = old_allocated;
      goto error;
    }
  }

  t->files[i].path = path;
  t->files[i].stat = stat;
  t->files[i].xattrs = xattrs;
  t->files[i].csum = csum;

  return 0;

 error:
  free (path);
  free (csum);
  guestfs_free_statns (stat);
  guestfs_free_xattr_list (xattrs);
  return -1;
}

static void deleted (guestfs_h *, struct file *);
static void added (guestfs_h *, struct file *);
static int compare_stats (struct file *, struct file *);
static void changed (guestfs_h *, struct file *, guestfs_h *, struct file *, int st, int cst);
static void diff (struct file *, guestfs_h *, struct file *, guestfs_h *);
static void output_file (guestfs_h *, struct file *);

static int
diff_guests (struct tree *t1, struct tree *t2)
{
  struct file *i1 = &t1->files[0];
  struct file *i2 = &t2->files[0];
  struct file *end1 = &t1->files[t1->nr_files];
  struct file *end2 = &t2->files[t2->nr_files];

  while (i1 < end1 || i2 < end2) {
    if (i1 < end1 && i2 < end2) {
      int comp = strcmp (i1->path, i2->path);

      /* i1->path < i2->path.  i1 catches up with i2 (files deleted) */
      if (comp < 0) {
        deleted (t1->g, i1);
        i1++;
      }
      /* i1->path > i2->path.  i2 catches up with i1 (files added) */
      else if (comp > 0) {
        added (t2->g, i2);
        i2++;
      }
      /* Otherwise i1->path == i2->path, compare in detail. */
      else {
        int st = compare_stats (i1, i2);
        if (st != 0)
          changed (t1->g, i1, t2->g, i2, st, 0);
        else if (i1->csum && i2->csum) {
          int cst = strcmp (i1->csum, i2->csum);
          changed (t1->g, i1, t2->g, i2, 0, cst);
        }
        i1++;
        i2++;
      }
    }
    /* Reached end of i2 list (files deleted). */
    else if (i1 < end1) {
      deleted (t1->g, i1);
      i1++;
    }
    /* Reached end of i1 list (files added). */
    else {
      added (t2->g, i2);
      i2++;
    }
  }

  output_flush ();

  return 0;
}

static void
deleted (guestfs_h *g, struct file *file)
{
  output_start_line ();
  output_string ("-");
  output_file (g, file);
  output_end_line ();
}

static void
added (guestfs_h *g, struct file *file)
{
  output_start_line ();
  output_string ("+");
  output_file (g, file);
  output_end_line ();
}

static int
compare_stats (struct file *file1, struct file *file2)
{
  int r;

  r = guestfs_compare_statns (file1->stat, file2->stat);
  if (r != 0)
    return r;

  r = guestfs_compare_xattr_list (file1->xattrs, file2->xattrs);
  if (r != 0)
    return r;

  return 0;
}

static void
changed (guestfs_h *g1, struct file *file1,
         guestfs_h *g2, struct file *file2,
         int st, int cst)
{
  /* Did file content change? */
  if (cst != 0 ||
      (is_reg (file1->stat->st_mode) && is_reg (file2->stat->st_mode) &&
       (file1->stat->st_mtime_sec != file2->stat->st_mtime_sec ||
        file1->stat->st_ctime_sec != file2->stat->st_ctime_sec ||
        file1->stat->st_size != file2->stat->st_size))) {
    output_start_line ();
    output_string ("=");
    output_file (g1, file1);
    output_end_line ();

    if (!csv) {
      /* Display file changes. */
      output_flush ();
      diff (file1, g1, file2, g2);
    }
  }

  /* Did just stats change? */
  else if (st != 0) {
    output_start_line ();
    output_string ("-");
    output_file (g1, file1);
    output_end_line ();
    output_start_line ();
    output_string ("+");
    output_file (g2, file2);
    output_end_line ();

    /* Display stats fields that changed. */
    output_start_line ();
    output_string ("#");
    output_string ("changed:");
#define COMPARE_STAT(n)						\
    if (file1->stat->n != file2->stat->n) output_string (#n)
    COMPARE_STAT (st_dev);
    COMPARE_STAT (st_ino);
    COMPARE_STAT (st_mode);
    COMPARE_STAT (st_nlink);
    COMPARE_STAT (st_uid);
    COMPARE_STAT (st_gid);
    COMPARE_STAT (st_rdev);
    COMPARE_STAT (st_size);
    COMPARE_STAT (st_blksize);
    COMPARE_STAT (st_blocks);
    COMPARE_STAT (st_atime_sec);
    COMPARE_STAT (st_mtime_sec);
    COMPARE_STAT (st_ctime_sec);
#undef COMPARE_STAT
    if (guestfs_compare_xattr_list (file1->xattrs, file2->xattrs))
      output_string ("xattrs");
    output_end_line ();
  }
}

/* Run a diff on two files. */
static void
diff (struct file *file1, guestfs_h *g1, struct file *file2, guestfs_h *g2)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g1);
  CLEANUP_FREE char *tmpd, *tmpda = NULL, *tmpdb = NULL, *cmd = NULL;
  int r;

  assert (is_reg (file1->stat->st_mode));
  assert (is_reg (file2->stat->st_mode));

  if (asprintf (&tmpd, "%s/virtdiffXXXXXX", tmpdir) < 0) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  if (mkdtemp (tmpd) == NULL) {
    perror ("mkdtemp");
    exit (EXIT_FAILURE);
  }

  if (asprintf (&tmpda, "%s/a", tmpd) < 0 ||
      asprintf (&tmpdb, "%s/b", tmpd) < 0) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }

  if (guestfs_download (g1, file1->path, tmpda) == -1)
    goto out;
  if (guestfs_download (g2, file2->path, tmpdb) == -1)
    goto out;

  /* Note that the tmpdir is safe, and the rest of the path
   * should not need quoting.
   */
  if (asprintf (&cmd, "diff -u '%s' '%s' | tail -n +3", tmpda, tmpdb) < 0) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);
  r = system (cmd);
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    fprintf (stderr, _("%s: external diff command failed\n"), guestfs_int_program_name);
    goto out;
  }

  printf ("@@ %s @@\n", _("End of diff"));

 out:
  unlink (tmpda);
  unlink (tmpdb);
  rmdir (tmpd);
}

static void
output_file (guestfs_h *g, struct file *file)
{
  const char *filetype;
  size_t i;
  CLEANUP_FREE char *link = NULL;

  if (is_reg (file->stat->st_mode))
    filetype = "-";
  else if (is_dir (file->stat->st_mode))
    filetype = "d";
  else if (is_chr (file->stat->st_mode))
    filetype = "c";
  else if (is_blk (file->stat->st_mode))
    filetype = "b";
  else if (is_fifo (file->stat->st_mode))
    filetype = "p";
  else if (is_lnk (file->stat->st_mode))
    filetype = "l";
  else if (is_sock (file->stat->st_mode))
    filetype = "s";
  else
    filetype = "u";

  output_string (filetype);
  output_int64_perms (file->stat->st_mode & 07777);

  output_int64_size (file->stat->st_size);

  /* Display extra fields when enabled. */
  if (enable_uids) {
    output_int64_uid (file->stat->st_uid);
    output_int64_uid (file->stat->st_gid);
  }

  if (enable_times) {
    if (atime)
      output_int64_time (file->stat->st_atime_sec, file->stat->st_atime_nsec);
    output_int64_time (file->stat->st_mtime_sec, file->stat->st_mtime_nsec);
    output_int64_time (file->stat->st_ctime_sec, file->stat->st_ctime_nsec);
  }

  if (enable_extra_stats) {
    output_int64_dev (file->stat->st_dev);
    output_int64 (file->stat->st_ino);
    output_int64 (file->stat->st_nlink);
    output_int64_dev (file->stat->st_rdev);
    output_int64 (file->stat->st_blocks);
  }

  if (file->csum)
    output_string (file->csum);

  output_string (file->path);

  if (is_lnk (file->stat->st_mode)) {
    /* XXX Fix this for NTFS. */
    link = guestfs_readlink (g, file->path);
    if (link)
      output_string_link (link);
  }

  if (enable_xattrs) {
    for (i = 0; i < file->xattrs->len; ++i) {
      output_string (file->xattrs->val[i].attrname);
      output_binary (file->xattrs->val[i].attrval,
                     file->xattrs->val[i].attrval_len);
    }
  }
}

/* Output functions.
 *
 * Note that we have to be careful to check return values from printf
 * in these functions, because we want to catch ENOSPC errors.
 */
static int field;
static void
next_field (void)
{
  int c = csv ? ',' : ' ';

  field++;
  if (field == 1) return;

  if (putchar (c) == EOF) {
    perror ("putchar");
    exit (EXIT_FAILURE);
  }
}

static void
output_start_line (void)
{
  field = 0;
}

static void
output_end_line (void)
{
  if (printf ("\n") < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}

static void
output_flush (void)
{
  if (fflush (stdout) == EOF) {
    perror ("fflush");
    exit (EXIT_FAILURE);
  }
}

static void
output_string (const char *s)
{
  next_field ();

  if (!csv) {
  print_no_quoting:
    if (printf ("%s", s) < 0) {
      perror ("printf");
      exit (EXIT_FAILURE);
    }
  }
  else {
    /* Quote CSV string without requiring an external module. */
    size_t i, len;
    int needs_quoting = 0;

    len = strlen (s);

    for (i = 0; i < len; ++i) {
      if (s[i] == ' ' || s[i] == '"' ||
          s[i] == '\n' || s[i] == ',') {
        needs_quoting = 1;
        break;
      }
    }

    if (!needs_quoting)
      goto print_no_quoting;

    /* Quoting for CSV fields. */
    if (putchar ('"') == EOF) {
      perror ("putchar");
      exit (EXIT_FAILURE);
    }
    for (i = 0; i < len; ++i) {
      if (s[i] == '"') {
        if (putchar ('"') == EOF || putchar ('"') == EOF) {
          perror ("putchar");
          exit (EXIT_FAILURE);
        }
      } else {
        if (putchar (s[i]) == EOF) {
          perror ("putchar");
          exit (EXIT_FAILURE);
        }
      }
    }
    if (putchar ('"') == EOF) {
      perror ("putchar");
      exit (EXIT_FAILURE);
    }
  }
}

static void
output_string_link (const char *link)
{
  if (csv)
    output_string (link);
  else {
    next_field ();

    if (printf ("-> %s", link) < 0) {
      perror ("printf");
      exit (EXIT_FAILURE);
    }
  }
}

static void
output_binary (const char *s, size_t len)
{
  size_t i;

  next_field ();

  if (!csv) {
  print_no_quoting:
    for (i = 0; i < len; ++i) {
      if (c_isprint (s[i])) {
        if (putchar (s[i]) == EOF) {
          perror ("putchar");
          exit (EXIT_FAILURE);
        }
      } else {
        if (printf ("\\x%02x", (unsigned char) s[i]) < 0) {
          perror ("printf");
          exit (EXIT_FAILURE);
        }
      }
    }
  }
  else {
    /* Quote CSV string without requiring an external module. */
    int needs_quoting = 0;

    for (i = 0; i < len; ++i) {
      if (!c_isprint (s[i]) || s[i] == ' ' || s[i] == '"' ||
          s[i] == '\n' || s[i] == ',') {
        needs_quoting = 1;
        break;
      }
    }

    if (!needs_quoting)
      goto print_no_quoting;

    /* Quoting for CSV fields. */
    if (putchar ('"') == EOF) {
      perror ("putchar");
      exit (EXIT_FAILURE);
    }
    for (i = 0; i < len; ++i) {
      if (s[i] == '"') {
        if (putchar ('"') == EOF || putchar ('"') == EOF) {
          perror ("putchar");
          exit (EXIT_FAILURE);
        }
      } else {
        if (c_isprint (s[i])) {
          if (putchar (s[i]) == EOF) {
            perror ("putchar");
            exit (EXIT_FAILURE);
          }
        } else {
          if (printf ("\\x%2x", (unsigned) s[i]) < 0) {
            perror ("printf");
            exit (EXIT_FAILURE);
          }
        }
      }
    }
    if (putchar ('"') == EOF) {
      perror ("putchar");
      exit (EXIT_FAILURE);
    }
  }
}

static void
output_int64 (int64_t i)
{
  next_field ();
  /* csv doesn't need escaping */
  if (printf ("%" PRIi64, i) < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}

static void
output_int64_size (int64_t size)
{
  char buf[LONGEST_HUMAN_READABLE];
  int hopts = human_round_to_nearest|human_autoscale|human_base_1024|human_SI;
  int r;

  next_field ();

  if (!csv) {
    if (!human)
      r = printf ("%10" PRIi64, size);
    else
      r = printf ("%10s",
                  human_readable ((uintmax_t) size, buf, hopts, 1, 1));
  } else {
    /* CSV is the same as non-CSV but we don't need to right-align. */
    if (!human)
      r = printf ("%" PRIi64, size);
    else
      r = printf ("%s",
                  human_readable ((uintmax_t) size, buf, hopts, 1, 1));
  }

  if (r < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}

static void
output_int64_perms (int64_t i)
{
  next_field ();
  /* csv doesn't need escaping */
  if (printf ("%04" PRIo64, (uint64_t) i) < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}

static void
output_int64_time (int64_t secs, int64_t nsecs)
{
  int r;

  next_field ();

  /* csv doesn't need escaping */
  if (time_t_output) {
    switch (time_relative) {
    case 0:                     /* --time-t */
      r = printf ("%10" PRIi64, secs);
      break;
    case 1:                     /* --time-relative */
      r = printf ("%8" PRIi64, now - secs);
      break;
    case 2:                     /* --time-days */
    default:
      r = printf ("%3" PRIi64, (now - secs) / 86400);
      break;
    }
  }
  else {
    time_t t = (time_t) secs;
    char buf[64];
    struct tm *tm;

    tm = localtime (&t);
    if (tm == NULL) {
      perror ("localtime");
      exit (EXIT_FAILURE);
    }

    if (strftime (buf, sizeof buf, "%F %T", tm) == 0) {
      perror ("strftime");
      exit (EXIT_FAILURE);
    }

    r = printf ("%s", buf);
  }

  if (r < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}

static void
output_int64_uid (int64_t i)
{
  next_field ();
  /* csv doesn't need escaping */
  if (printf (csv ? "%" PRIi64 : "%4" PRIi64, i) < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}

static void
output_int64_dev (int64_t i)
{
  dev_t dev = i;

  next_field ();

  /* csv doesn't need escaping */
  if (printf ("%ju:%ju",
              (uintmax_t) major (dev), (uintmax_t) minor (dev)) < 0) {
    perror ("printf");
    exit (EXIT_FAILURE);
  }
}
