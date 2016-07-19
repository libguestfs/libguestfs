/* virt-make-fs
 * Copyright (C) 2010-2016 Red Hat Inc.
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
#include <libintl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "xstrtol.h"

#include "options.h"

guestfs_h *g;
const char *libvirt_uri;
int live;
int read_only;
int verbose;

static const char *format = "raw", *label = NULL,
  *partition = NULL, *size_str = NULL, *type = "ext2";

enum { HELP_OPTION = CHAR_MAX + 1 };
static const char *options = "F:s:t:Vvx";
static const struct option long_options[] = {
  { "debug", 0, 0, 'v' }, /* for compat with Perl tool */
  { "floppy", 0, 0, 0 },
  { "format", 1, 0, 'F' },
  { "help", 0, 0, HELP_OPTION },
  { "label", 1, 0, 0 },
  { "long-options", 0, 0, 0 },
  { "partition", 2, 0, 0 },
  { "short-options", 0, 0, 0 },
  { "size", 1, 0, 's' },
  { "type", 1, 0, 't' },
  { "verbose", 0, 0, 'v' },
  { "version", 0, 0, 'V' },
  { 0, 0, 0, 0 }
};

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             guestfs_int_program_name);
  else {
    printf (_("%s: make a filesystem from a tar archive or files\n"
              "Copyright (C) 2010-2016 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] input.tar output.img\n"
              "  %s [--options] input.tar.gz output.img\n"
              "  %s [--options] directory output.img\n"
              "Options:\n"
              "  --floppy                 Make a virtual floppy disk\n"
              "  -F|--format=raw|qcow2|.. Set output format\n"
              "  --help                   Display brief help\n"
              "  --label=label            Filesystem label\n"
              "  --partition=mbr|gpt|..   Set partition type\n"
              "  -s|--size=size|+size     Set size of output disk\n"
              "  -t|--type=ext4|..        Set filesystem type\n"
              "  -v|--verbose             Verbose messages\n"
              "  -V|--version             Display version and exit\n"
              "  -x                       Trace libguestfs API calls\n"
              "For more information, see the manpage %s(1).\n"),
            guestfs_int_program_name, guestfs_int_program_name,
            guestfs_int_program_name, guestfs_int_program_name,
            guestfs_int_program_name);
  }
  exit (status);
}

static int do_make_fs (const char *input, const char *output_str);

int
main (int argc, char *argv[])
{
  int c;
  int option_index;

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options")) {
        display_long_options (long_options);
      }
      else if (STREQ (long_options[option_index].name, "short-options")) {
        display_short_options (options);
      }
      else if (STREQ (long_options[option_index].name, "floppy")) {
        size_str = "1440K";
        partition = "mbr";
        type = "vfat";
      }
      else if (STREQ (long_options[option_index].name, "label")) {
        label = optarg;
      }
      else if (STREQ (long_options[option_index].name, "partition")) {
        if (optarg == NULL)
          partition = "mbr";
        else
          partition = optarg;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 guestfs_int_program_name,
                 long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'F':
      format = optarg;
      break;

    case 's':
      size_str = optarg;
      break;

    case 't':
      type = optarg;
      break;

    case 'v':
      OPTION_v;
      break;

    case 'V':
      OPTION_V;
      break;

    case 'x':
      OPTION_x;
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (optind + 2 != argc) {
    fprintf (stderr,
             _("%s: missing input and output arguments on the command line\n"),
             guestfs_int_program_name);
    usage (EXIT_FAILURE);
  }

  if (do_make_fs (argv[optind], argv[optind+1]) == -1)
    exit (EXIT_FAILURE);

  exit (EXIT_SUCCESS);
}

static int
check_ntfs_available (void)
{
  const char *ntfs_features[] = { "ntfs3g", "ntfsprogs", NULL };

  if (STREQ (type, "ntfs") &&
      guestfs_feature_available (g, (char **) ntfs_features) == 0) {
    fprintf (stderr,
             _("%s: NTFS support was disabled when libguestfs was compiled\n"),
             guestfs_int_program_name);
    return -1;
  }

  return 0;
}

/* For debugging, print statvfs before and after doing the tar-in. */
static void
print_stats (guestfs_h *g, const char *before_or_after)
{
  if (!verbose)
    return;

  CLEANUP_FREE_STATVFS struct guestfs_statvfs *stats = guestfs_statvfs (g, "/");
  if (stats) {
    fprintf (stderr, "%s uploading:\n", before_or_after);
    fprintf (stderr, "  bsize = %" PRIi64 "\n", stats->bsize);
    fprintf (stderr, "  frsize = %" PRIi64 "\n", stats->frsize);
    fprintf (stderr, "  blocks = %" PRIi64 "\n", stats->blocks);
    fprintf (stderr, "  bfree = %" PRIi64 "\n", stats->bfree);
    fprintf (stderr, "  bavail = %" PRIi64 "\n", stats->bavail);
    fprintf (stderr, "  files = %" PRIi64 "\n", stats->files);
    fprintf (stderr, "  ffree = %" PRIi64 "\n", stats->ffree);
    fprintf (stderr, "  favail = %" PRIi64 "\n", stats->favail);
    fprintf (stderr, "  fsid = %" PRIi64 "\n", stats->fsid);
    fprintf (stderr, "  flag = %" PRIi64 "\n", stats->flag);
    fprintf (stderr, "  namemax = %" PRIi64 "\n", stats->namemax);
  }
}

/* Execute a command, sending output to a file. */
static int
exec_command (char **argv, const char *file)
{
  pid_t pid;
  int status, fd;

  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    return -1;
  }
  if (pid > 0) {
    if (waitpid (pid, &status, 0) == -1) {
      perror ("waitpid");
      return -1;
    }
    if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      fprintf (stderr, _("%s: %s command failed\n"),
               guestfs_int_program_name, argv[0]);
      return -1;
    }
    return 0;
  }

  /* Child process. */
  fd = open (file, O_WRONLY|O_NOCTTY);
  if (fd == -1) {
    perror (file);
    _exit (EXIT_FAILURE);
  }
  dup2 (fd, 1);
  close (fd);

  execvp (argv[0], argv);
  perror ("execvp");
  _exit (EXIT_FAILURE);
}

/* Execute a command, counting the amount of bytes output. */
static int
exec_command_count_output (char **argv, uint64_t *bytes_rtn)
{
  pid_t pid;
  int status;
  int fd[2];
  char buffer[BUFSIZ];
  ssize_t r;

  if (pipe (fd) == -1) {
    perror ("pipe");
    return -1;
  }
  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    return -1;
  }
  if (pid > 0) {
    close (fd[1]);

    /* Read output from the subprocess and count the length. */
    while ((r = read (fd[0], buffer, sizeof buffer)) > 0) {
      *bytes_rtn += r;
    }
    if (r == -1) {
      perror ("read");
      return -1;
    }
    close (fd[0]);

    if (waitpid (pid, &status, 0) == -1) {
      perror ("waitpid");
      return -1;
    }
    if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      fprintf (stderr, _("%s: %s command failed\n"),
               guestfs_int_program_name, argv[0]);
      return -1;
    }
    return 0;
  }

  /* Child process. */
  close (fd[0]);
  dup2 (fd[1], 1);
  close (fd[1]);

  execvp (argv[0], argv);
  perror ("execvp");
  _exit (EXIT_FAILURE);
}

/* Execute a command in the background (don't wait) and send the
 * output to a pipe.  It returns the PID of the subprocess and the
 * file descriptor of the pipe.
 */
static int
bg_command (char **argv, int *fd_rtn, pid_t *pid_rtn)
{
  int fd[2];

  if (pipe (fd) == -1) {
    perror ("pipe");
    return -1;
  }
  *pid_rtn = fork ();
  if (*pid_rtn == -1) {
    perror ("fork");
    return -1;
  }
  if (*pid_rtn > 0) {
    close (fd[1]);

    /* Return read-side of the pipe. */
    *fd_rtn = fd[0];

    /* Return immediately in the parent without waiting. */
    return 0;
  }

  /* Child process. */
  close (fd[0]);
  dup2 (fd[1], 1);
  close (fd[1]);

  execvp (argv[0], argv);
  perror ("execvp");
  _exit (EXIT_FAILURE);
}

/* Estimate the size of the input.  This returns the estimated size
 * (in bytes) of the input.  It also sets ifmt to the format of the
 * input, either the string "directory" if the input is a directory,
 * or the output of the "file" command on the input.
 *
 * Estimation is a Hard Problem.  Some factors which make it hard:
 *
 *   - Superblocks, block free bitmaps, FAT and other fixed overhead
 *   - Indirect blocks (ext2, ext3), and extents
 *   - Journal size
 *   - Internal fragmentation of files
 *
 * What we could also do is try shrinking the filesystem after
 * creating and populating it, but that is complex given partitions.
 */
static int
estimate_input (const char *input, uint64_t *estimate_rtn, char **ifmt_rtn)
{
  struct stat statbuf;
  const char *argv[6];
  CLEANUP_UNLINK_FREE char *tmpfile = NULL;
  CLEANUP_FCLOSE FILE *fp = NULL;
  char line[256];
  size_t len;
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
  int fd;

  if (asprintf (&tmpfile, "%s/makefsXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    return -1;
  }
  fd = mkstemp (tmpfile);
  if (fd == -1) {
    perror (tmpfile);
    return -1;
  }
  close (fd);

  if (stat (input, &statbuf) == -1) {
    perror (input);
    return -1;
  }
  if (S_ISDIR (statbuf.st_mode)) {
    *ifmt_rtn = strdup ("directory");
    if (*ifmt_rtn == NULL) {
      perror ("strdup");
      return -1;
    }

    argv[0] = "du";
    argv[1] = "--apparent-size";
    argv[2] = "-b";
    argv[3] = "-s";
    argv[4] = input;
    argv[5] = NULL;

    if (exec_command ((char **) argv, tmpfile) == -1)
      return -1;

    fp = fopen (tmpfile, "r");
    if (fp == NULL) {
      perror (tmpfile);
      return -1;
    }
    if (fgets (line, sizeof line, fp) == NULL) {
      perror ("fgets");
      return -1;
    }

    if (sscanf (line, "%" SCNu64, estimate_rtn) != 1) {
      fprintf (stderr, _("%s: cannot parse the output of 'du' command: %s\n"),
               guestfs_int_program_name, line);
      return -1;
    }
  }
  else {
    argv[0] = "file";
    argv[1] = "-bsLz";
    argv[2] = input;
    argv[3] = NULL;

    if (exec_command ((char **) argv, tmpfile) == -1)
      return -1;

    fp = fopen (tmpfile, "r");
    if (fp == NULL) {
      perror (tmpfile);
      return -1;
    }
    if (fgets (line, sizeof line, fp) == NULL) {
      perror ("fgets");
      return -1;
    }

    len = strlen (line);
    if (len > 0 && line[len-1] == '\n')
      line[len-1] = '\0';

    *ifmt_rtn = strdup (line);
    if (*ifmt_rtn == NULL) {
      perror ("strdup");
      return -1;
    }

    if (strstr (line, "tar archive") == NULL) {
      fprintf (stderr, _("%s: %s: input is not a directory, tar archive or compressed tar archive\n"),
               guestfs_int_program_name, input);
      return -1;
    }

    if (strstr (line, "compress")) {
      if (strstr (line, "compress'd")) {
        argv[0] = "uncompress";
        argv[1] = "-c";
        argv[2] = input;
        argv[3] = NULL;
      }
      else if (strstr (line, "gzip compressed")) {
        argv[0] = "gzip";
        argv[1] = "-cd";
        argv[2] = input;
        argv[3] = NULL;
      }
      else if (strstr (line, "bzip2 compressed")) {
        argv[0] = "bzip2";
        argv[1] = "-cd";
        argv[2] = input;
        argv[3] = NULL;
      }
      else if (strstr (line, "xz compressed")) {
        argv[0] = "xz";
        argv[1] = "-cd";
        argv[2] = input;
        argv[3] = NULL;
      }
      else {
        fprintf (stderr, _("%s: %s: unknown compressed input format (%s)\n"),
                 guestfs_int_program_name, input, line);
        return -1;
      }

      *estimate_rtn = 0;
      if (exec_command_count_output ((char **) argv, estimate_rtn) == -1)
        return -1;
    }
    else {
      /* Plain tar file, just get the size directly.  Tar files have
       * a 512 byte block size (compared with typically 1K or 4K for
       * filesystems) so this isn't very accurate.
       */
      *estimate_rtn = statbuf.st_size;
    }
  }

  return 0;
}

/* Prepare the input source.  If the input is a regular tar file, this
 * just sets ifile = input.  However normally the input will be either
 * a directory or a compressed tarball.  In that case we set up an
 * external command to do the tar/uncompression to a temporary pipe,
 * and set ifile to the name of the pipe.  If there is a subprocess,
 * the PID is returned so that callers can wait on it.
 */
static int
prepare_input (const char *input, const char *ifmt,
               char **ifile_rtn, int *fd_rtn, pid_t *pid_rtn)
{
  const char *argv[7];

  *pid_rtn = 0;
  *fd_rtn = -1;

  if (STREQ (ifmt, "directory")) {
    argv[0] = "tar";
    argv[1] = "-C";
    argv[2] = input;
    argv[3] = "-cf";
    argv[4] = "-";
    argv[5] = ".";
    argv[6] = NULL;

    if (bg_command ((char **) argv, fd_rtn, pid_rtn) == -1)
      return -1;

    if (asprintf (ifile_rtn, "/dev/fd/%d", *fd_rtn) == -1) {
      perror ("asprintf");
      return -1;
    }
  }
  else {
    if (strstr (ifmt, "compress")) {
      if (strstr (ifmt, "compress'd")) {
        argv[0] = "uncompress";
        argv[1] = "-c";
        argv[2] = input;
        argv[3] = NULL;
      }
      else if (strstr (ifmt, "gzip compressed")) {
        argv[0] = "gzip";
        argv[1] = "-cd";
        argv[2] = input;
        argv[3] = NULL;
      }
      else if (strstr (ifmt, "bzip2 compressed")) {
        argv[0] = "bzip2";
        argv[1] = "-cd";
        argv[2] = input;
        argv[3] = NULL;
      }
      else if (strstr (ifmt, "xz compressed")) {
        argv[0] = "xz";
        argv[1] = "-cd";
        argv[2] = input;
        argv[3] = NULL;
      }
      else
        /* Shouldn't happen - see estimate_input above. */
        abort ();

      if (bg_command ((char **) argv, fd_rtn, pid_rtn) == -1)
        return -1;

      if (asprintf (ifile_rtn, "/dev/fd/%d", *fd_rtn) == -1) {
        perror ("asprintf");
        return -1;
      }
    }
    else {
      /* Plain tar file, read directly from the file. */
      *ifile_rtn = strdup (input);
      if (*ifile_rtn == NULL) {
        perror ("strdup");
        return -1;
      }
    }
  }

  return 0;
}

/* Adapted from fish/alloc.c */
static int
parse_size (const char *str, uint64_t estimate, uint64_t *size_rtn)
{
  unsigned long long size;
  strtol_error xerr;
  int plus = 0;

  assert (str);

  if (str[0] == '+') {
    plus = 1;
    str++;
  }

  xerr = xstrtoull (str, NULL, 0, &size, "0kKMGTPEZY");
  if (xerr != LONGINT_OK) {
    fprintf (stderr,
             _("%s: %s: invalid size parameter '%s' (%s returned %u)\n"),
             guestfs_int_program_name, "parse_size", str, "xstrtoull", xerr);
    return -1;
  }

  if (plus)
    *size_rtn = estimate + size;
  else
    *size_rtn = size;

  return 0;
}

static int
do_make_fs (const char *input, const char *output_str)
{
  const char *dev, *options;
  CLEANUP_UNLINK_FREE char *output = NULL;
  uint64_t estimate, size;
  struct guestfs_disk_create_argv optargs;
  CLEANUP_FREE char *ifmt = NULL;
  CLEANUP_FREE char *ifile = NULL;
  pid_t pid;
  int status, fd;

  /* Use of CLEANUP_UNLINK_FREE *output ensures the output file is
   * deleted unless we successfully reach the end of this function.
   */
  output = strdup (output_str);
  if (output == NULL) {
    perror ("strdup");
    return -1;
  }

  /* Input.  What is it?  Estimate how much space it will need. */
  if (estimate_input (input, &estimate, &ifmt) == -1)
    return -1;

  if (verbose) {
    fprintf (stderr, "input format = %s\n", ifmt);
    fprintf (stderr, "estimate = %" PRIu64 " bytes "
             "(%" PRIu64 " 1K blocks, %" PRIu64 " 4K blocks)\n",
             estimate, estimate / 1024, estimate / 4096);
  }

  estimate += 256 * 1024;       /* For superblocks &c. */

  if (STRPREFIX (type, "ext") && type[3] >= '3') {
    /* For ext3+, add some more for the journal. */
    estimate += 1024 * 1024;
  }

  else if (STREQ (type, "ntfs")) {
    estimate += 4 * 1024 * 1024; /* NTFS journal. */
  }

  else if (STREQ (type, "btrfs")) {
    /* For BTRFS, the minimum metadata allocation is 256MB, with data
     * additional to that.  Note that we disable data and metadata
     * duplication below.
     */
    estimate += 256 * 1024 * 1024;
  }

  /* Add 10%, see above. */
  estimate *= 1.10;

  /* Calculate the output size. */
  if (size_str == NULL)
    size = estimate;
  else
    if (parse_size (size_str, estimate, &size) == -1)
      return -1;

  /* Create the output disk. */
  optargs.bitmask = 0;
  if (STREQ (format, "qcow2")) {
    optargs.bitmask |= GUESTFS_DISK_CREATE_PREALLOCATION_BITMASK;
    optargs.preallocation = "metadata";
  }
  if (guestfs_disk_create_argv (g, output, format, size, &optargs) == -1)
    return -1;

  if (guestfs_add_drive_opts (g, output,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, format,
                              -1) == -1)
    return -1;

  if (guestfs_launch (g) == -1)
    return -1;

  if (check_ntfs_available () == -1)
    return -1;

  /* Partition the disk. */
  dev = "/dev/sda";
  if (partition) {
    int mbr_id = 0;

    if (STREQ (partition, ""))
      partition = "mbr";

    if (guestfs_part_disk (g, dev, partition) == -1)
      return -1;

    dev = "/dev/sda1";

    /* Set the partition type byte if it's MBR and the filesystem type
     * is one that we know about.
     */
    if (STREQ (partition, "mbr") || STREQ (partition, "msdos")) {
      if (STREQ (type, "msdos"))
        /* According to Wikipedia.  However I have not actually tried this. */
        mbr_id = 0x1;
      else if (STREQ (type, "vfat") || STREQ (type, "fat"))
        mbr_id = 0xb;
      else if (STREQ (type, "ntfs"))
        mbr_id = 0x7;
      else if (STRPREFIX (type, "ext"))
        mbr_id = 0x83;
      else if (STREQ (type, "minix"))
        mbr_id = 0x81;
    }
    if (mbr_id != 0) {
      if (guestfs_part_set_mbr_id (g, "/dev/sda", 1, mbr_id) == -1)
        return -1;
    }
  }

  if (verbose)
    fprintf (stderr, "creating %s filesystem on %s ...\n", type, dev);

  /* Create the filesystem. */
  if (STRNEQ (type, "btrfs")) {
    int r;
    struct guestfs_mkfs_opts_argv optargs = { .bitmask = 0 };

    if (label) {
      optargs.label = label;
      optargs.bitmask |= GUESTFS_MKFS_OPTS_LABEL_BITMASK;
    }

    guestfs_push_error_handler (g, NULL, NULL);
    r = guestfs_mkfs_opts_argv (g, type, dev, &optargs);
    guestfs_pop_error_handler (g);

    if (r == -1) {
      /* Provide more guidance in the error message (RHBZ#823883). */
      fprintf (stderr, "%s: 'mkfs' (create filesystem) operation failed: %s\n",
               guestfs_int_program_name, guestfs_last_error (g));
      if (STREQ (type, "fat"))
        fprintf (stderr, "Instead of 'fat', try 'vfat' (long filenames) or 'msdos' (short filenames).\n");
      else
        fprintf (stderr, "Is '%s' a correct filesystem type?\n", type);

      return -1;
    }
  }
  else {
    const char *devs[] = { dev, NULL };
    struct guestfs_mkfs_btrfs_argv optargs = { .bitmask = 0 };

    optargs.datatype = "single";
    optargs.metadata = "single";
    optargs.bitmask |= GUESTFS_MKFS_BTRFS_DATATYPE_BITMASK | GUESTFS_MKFS_BTRFS_METADATA_BITMASK;
    if (label) {
      optargs.label = label;
      optargs.bitmask |= GUESTFS_MKFS_BTRFS_LABEL_BITMASK;
    }

    if (guestfs_mkfs_btrfs_argv (g, (char **) devs, &optargs) == -1)
      return -1;
  }

  /* Mount it. */

  /* For vfat, add the utf8 mount option because we want to be able to
   * encode any non-ASCII characters into UCS2 which is what modern
   * vfat uses on disk (RHBZ#823885).
   */
  if (STREQ (type, "vfat"))
    options = "utf8";
  else
    options = "";

  if (guestfs_mount_options (g, options, dev, "/") == -1)
    return -1;

  print_stats (g, "before");

  /* Prepare the input to be copied in. */
  if (prepare_input (input, ifmt, &ifile, &fd, &pid) == -1)
    return -1;

  if (verbose)
    fprintf (stderr, "uploading from %s to / ...\n", ifile);
  if (guestfs_tar_in (g, ifile, "/") == -1)
    return -1;

  /* Clean up subprocess. */
  if (pid > 0) {
    if (waitpid (pid, &status, 0) == -1) {
      perror ("waitpid");
      return -1;
    }
    if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      fprintf (stderr, _("%s: subprocess failed\n"), guestfs_int_program_name);
      return -1;
    }
  }
  if (fd >= 0)
    close (fd);

  print_stats (g, "after");

  if (verbose)
    fprintf (stderr, "finishing off\n");
  if (guestfs_shutdown (g) == -1)
    return -1;
  guestfs_close (g);

  /* Output was created OK, so save it from being deleted by
   * CLEANUP_UNLINK_FREE.
   */
  free (output);
  output = NULL;

  return 0;
}
