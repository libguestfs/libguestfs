/* virt-rescue
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include "ignore-value.h"
#include "progname.h"
#include "xvasprintf.h"

#include "guestfs.h"
#include "options.h"

static void add_scratch_disks (int n, struct drv **drvs);
static void do_suggestion (struct drv *drvs);

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 0;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;

static inline char *
bad_cast (char const *s)
{
  return (char *) s;
}

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             program_name);
  else {
    fprintf (stdout,
           _("%s: Run a rescue shell on a virtual machine\n"
             "Copyright (C) 2009-2012 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname\n"
             "  %s [--options] -a disk.img [-a disk.img ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  --append kernelopts  Append kernel options\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  -m|--memsize MB      Set memory size in megabytes\n"
             "  --network            Enable network\n"
             "  -r|--ro              Access read-only\n"
             "  --scratch[=N]        Add scratch disk(s)\n"
             "  --selinux            Enable SELinux\n"
             "  --smp N              Enable SMP with N >= 2 virtual CPUs\n"
             "  --suggest            Suggest mount commands for this guest\n"
             "  -v|--verbose         Verbose messages\n"
             "  -V|--version         Display version and exit\n"
             "  -w|--rw              Mount read-write\n"
             "  -x                   Trace libguestfs API calls\n"
             "For more information, see the manpage %s(1).\n"),
             program_name, program_name, program_name,
             program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  /* Set global program name that is not polluted with libtool artifacts.  */
  set_program_name (argv[0]);

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  parse_config ();

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:c:d:m:rvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "append", 1, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "memsize", 1, 0, 'm' },
    { "network", 0, 0, 0 },
    { "ro", 0, 0, 'r' },
    { "rw", 0, 0, 'w' },
    { "scratch", 2, 0, 0 },
    { "selinux", 0, 0, 0 },
    { "smp", 1, 0, 0 },
    { "suggest", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  int c;
  int option_index;
  int network = 0;
  const char *append = NULL;
  char *append_full;
  int memsize = 0;
  int smp = 0;
  int suggest = 0;

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  argv[0] = bad_cast (program_name);

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "selinux")) {
        guestfs_set_selinux (g, 1);
      } else if (STREQ (long_options[option_index].name, "append")) {
        append = optarg;
      } else if (STREQ (long_options[option_index].name, "network")) {
        network = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        if (!optarg || STREQ (optarg, ""))
          format = NULL;
        else
          format = optarg;
      } else if (STREQ (long_options[option_index].name, "smp")) {
        if (sscanf (optarg, "%u", &smp) != 1) {
          fprintf (stderr, _("%s: could not parse --smp parameter '%s'\n"),
                   program_name, optarg);
          exit (EXIT_FAILURE);
        }
        if (smp < 1) {
          fprintf (stderr, _("%s: --smp parameter '%s' should be >= 1\n"),
                   program_name, optarg);
          exit (EXIT_FAILURE);
        }
      } else if (STREQ (long_options[option_index].name, "suggest")) {
        suggest = 1;
      } else if (STREQ (long_options[option_index].name, "scratch")) {
        if (!optarg || STREQ (optarg, ""))
          add_scratch_disks (1, &drvs);
        else {
          int n;
          if (sscanf (optarg, "%d", &n) != 1) {
            fprintf (stderr,
                     _("%s: could not parse --scratch parameter '%s'\n"),
                     program_name, optarg);
            exit (EXIT_FAILURE);
          }
          if (n < 1) {
            fprintf (stderr,
                     _("%s: --scratch parameter '%s' should be >= 1\n"),
                     program_name, optarg);
            exit (EXIT_FAILURE);
          }
          add_scratch_disks (n, &drvs);
        }
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 program_name, long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'a':
      OPTION_a;
      break;

    case 'c':
      OPTION_c;
      break;

    case 'd':
      OPTION_d;
      break;

    case 'm':
      if (sscanf (optarg, "%u", &memsize) != 1) {
        fprintf (stderr, _("%s: could not parse memory size '%s'\n"),
                 program_name, optarg);
        exit (EXIT_FAILURE);
      }
      break;

    case 'r':
      OPTION_r;
      break;

    case 'v':
      OPTION_v;
      break;

    case 'V':
      OPTION_V;
      break;

    case 'w':
      OPTION_w;
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

  /* Old-style syntax?  There were no -a or -d options in the old
   * virt-rescue which is how we detect this.
   */
  if (drvs == NULL) {
    while (optind < argc) {
      if (strchr (argv[optind], '/') ||
          access (argv[optind], F_OK) == 0) { /* simulate -a option */
        drv = calloc (1, sizeof (struct drv));
        if (!drv) {
          perror ("malloc");
          exit (EXIT_FAILURE);
        }
        drv->type = drv_a;
        drv->a.filename = argv[optind];
        drv->next = drvs;
        drvs = drv;
      } else {                  /* simulate -d option */
        drv = calloc (1, sizeof (struct drv));
        if (!drv) {
          perror ("malloc");
          exit (EXIT_FAILURE);
        }
        drv->type = drv_d;
        drv->d.guest = argv[optind];
        drv->next = drvs;
        drvs = drv;
      }

      optind++;
    }
  }

  /* --suggest flag */
  if (suggest) {
    do_suggestion (drvs);
    exit (EXIT_SUCCESS);
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (inspector == 0);
  assert (keys_from_stdin == 0);
  assert (echo_keys == 0);
  assert (live == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  /* User must have specified some drives. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Setting "direct mode" is required for the rescue appliance. */
  guestfs_set_direct (g, 1);

  /* Set other features. */
  if (memsize > 0)
    guestfs_set_memsize (g, memsize);
  if (network)
    guestfs_set_network (g, 1);
  if (smp >= 1)
    guestfs_set_smp (g, smp);

  /* Kernel command line must include guestfs_rescue=1 (see
   * appliance/init) as well as other options.
   */
  append_full = xasprintf ("guestfs_rescue=1%s%s",
                           append ? " " : "",
                           append ? append : "");
  guestfs_set_append (g, append_full);
  free (append_full);

  /* Add drives. */
  add_drives (drvs, 'a');

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  /* Run the appliance.  This won't return until the user quits the
   * appliance.
   */
  if (!verbose)
    guestfs_set_error_handler (g, NULL, NULL);

  /* We expect launch to fail, so ignore the return value, and don't
   * bother with explicit guestfs_shutdown either.
   */
  ignore_value (guestfs_launch (g));

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void suggest_filesystems (void);

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strlen (key1) - strlen (key2);
}

static size_t
count_strings (char *const *argv)
{
  size_t i;

  for (i = 0; argv[i]; ++i)
    ;
  return i;
}

/* virt-rescue --suggest flag does a kind of inspection on the
 * drives and suggests mount commands that you should use.
 */
static void
do_suggestion (struct drv *drvs)
{
  char **roots;
  size_t i, j;
  char *type, *distro, *product_name;
  int major, minor;
  char **mps;

  /* For inspection, force add_drives to add the drives read-only. */
  read_only = 1;

  /* Add drives. */
  add_drives (drvs, 'a');

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  printf (_("Inspecting the virtual machine or disk image ...\n\n"));
  fflush (stdout);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Don't use inspect_mount, since for virt-rescue we should allow
   * arbitrary disks and disks with more than one OS on them.  Let's
   * do this using the basic API instead.
   */
  roots = guestfs_inspect_os (g);
  if (roots == NULL)
    exit (EXIT_FAILURE);

  if (roots[0] == NULL) {
    suggest_filesystems ();
    return;
  }

  printf (_("This disk contains one or more operating systems.  You can use these mount\n"
            "commands in virt-rescue (at the ><rescue> prompt) to mount the filesystems.\n\n"));

  for (i = 0; roots[i] != NULL; ++i) {
    type = guestfs_inspect_get_type (g, roots[i]);
    distro = guestfs_inspect_get_distro (g, roots[i]);
    product_name = guestfs_inspect_get_product_name (g, roots[i]);
    major = guestfs_inspect_get_major_version (g, roots[i]);
    minor = guestfs_inspect_get_minor_version (g, roots[i]);

    printf (_("# %s is the root of a %s operating system\n"
              "# type: %s, distro: %s, version: %d.%d\n"
              "# %s\n\n"),
            roots[i], type ? : "unknown",
            type ? : "unknown", distro ? : "unknown", major, minor,
            product_name ? : "");

    mps = guestfs_inspect_get_mountpoints (g, roots[i]);
    if (mps == NULL)
      exit (EXIT_FAILURE);

    /* Sort by key length, shortest key first, so that we end up
     * mounting the filesystems in the correct order.
     */
    qsort (mps, count_strings (mps) / 2, 2 * sizeof (char *),
           compare_keys_len);

    for (j = 0; mps[j] != NULL; j += 2) {
      printf ("mount %s /sysroot%s\n", mps[j+1], mps[j]);
      free (mps[j]);
      free (mps[j+1]);
    }

    /* If it's Linux, print the bind-mounts. */
    if (type && STREQ (type, "linux")) {
      printf ("mount --bind /dev /sysroot/dev\n");
      printf ("mount --bind /dev/pts /sysroot/dev/pts\n");
      printf ("mount --bind /proc /sysroot/proc\n");
      printf ("mount --bind /sys /sysroot/sys\n");
    }

    printf ("\n");

    free (type);
    free (distro);
    free (product_name);
    free (roots[i]);
  }

  free (roots);
}

/* Inspection failed, so it doesn't contain any OS that we recognise.
 * However there might still be filesystems so print some suggestions
 * for those.
 */
static void
suggest_filesystems (void)
{
  char **fses;
  size_t i;

  fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    exit (EXIT_FAILURE);

  if (fses[0] == NULL) {
    printf (_("This disk contains no filesystems that we recognize.\n\n"
              "However you can still use virt-rescue on the disk image, to try to mount\n"
              "filesystems that are not recognized by libguestfs, or to create partitions,\n"
              "logical volumes and filesystems on a blank disk.\n"));
    return;
  }

  printf (_("This disk contains one or more filesystems, but we don't recognize any\n"
            "operating system.  You can use these mount commands in virt-rescue (at the\n"
            "><rescue> prompt) to mount these filesystems.\n\n"));

  for (i = 0; fses[i] != NULL; i += 2) {
    printf (_("# %s has type '%s'\n"), fses[i], fses[i+1]);

    if (STRNEQ (fses[i+1], "swap") && STRNEQ (fses[i+1], "unknown"))
      printf ("mount %s /sysroot\n", fses[i]);

    printf ("\n");

    free (fses[i]);
    free (fses[i+1]);
  }
  free (fses);
}

struct scratch_disk {
  struct scratch_disk *next;
  char *filename;
};
static struct scratch_disk *scratch_disks = NULL;

static void unlink_scratch_disks (void);
static void add_scratch_disk (struct drv **drvs);

static void
add_scratch_disks (int n, struct drv **drvs)
{
  while (n > 0) {
    add_scratch_disk (drvs);
    n--;
  }
}

static void
add_scratch_disk (struct drv **drvs)
{
  char filename_s[] = "/var/tmp/rescueXXXXXX";
  int fd;
  char *filename;
  struct scratch_disk *sd;
  struct drv *drv;

  /* Create a temporary file, raw sparse format. */
  fd = mkstemp (filename_s);
  if (fd == -1) {
    perror ("mkstemp: scratch disk");
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, 10737418240ULL) == -1) {
    perror ("ftruncate: scratch disk");
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror ("close: scratch disk");
    exit (EXIT_FAILURE);
  }

  filename = strdup (filename_s);
  if (filename == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }

  /* Remember this scratch disk, so we can clean it up at exit. */
  if (scratch_disks == NULL)
    atexit (unlink_scratch_disks);
  sd = malloc (sizeof (struct scratch_disk));
  if (!sd) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
  sd->filename = filename;
  sd->next = scratch_disks;
  scratch_disks = sd;

  /* Add the scratch disk to the drives list. */
  drv = calloc (1, sizeof (struct drv));
  if (!drv) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
  drv->type = drv_a;
  drv->nr_drives = -1;
  drv->a.filename = filename;
  drv->a.format = "raw";
  drv->next = *drvs;
  *drvs = drv;
}

/* Called atexit to unlink the scratch disks. */
static void
unlink_scratch_disks (void)
{
  while (scratch_disks) {
    unlink (scratch_disks->filename);
    free (scratch_disks->filename);
    scratch_disks = scratch_disks->next;
  }
}

/* The following was a nice idea, but in fact it doesn't work.  This is
 * because qemu has some (broken) pty emulation itself.
 */
#if 0
  int fd_m, fd_s, r;
  pid_t pid;
  struct termios tsorig, tsnew;

  /* Set up pty. */
  fd_m = posix_openpt (O_RDWR);
  if (fd_m == -1) {
    perror ("posix_openpt");
    exit (EXIT_FAILURE);
  }
  r = grantpt (fd_m);
  if (r == -1) {
    perror ("grantpt");
    exit (EXIT_FAILURE);
  }
  r = unlockpt (fd_m);
  if (r == -1) {
    perror ("unlockpt");
    exit (EXIT_FAILURE);
  }
  fd_s = open (ptsname (fd_m), O_RDWR);
  if (fd_s == -1) {
    perror ("open ptsname");
    exit (EXIT_FAILURE);
  }

  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    exit (EXIT_FAILURE);
  }
  if (pid == 0) {
    /* Child process. */

#if 1
    /* Set raw mode. */
    r = tcgetattr (fd_s, &tsorig);
    tsnew = tsorig;
    cfmakeraw (&tsnew);
    tcsetattr (fd_s, TCSANOW, &tsnew);
#endif

    /* Close the master side of pty and set slave side as
     * stdin/stdout/stderr.
     */
    close (fd_m);

    close (0);
    close (1);
    close (2);
    if (dup (fd_s) == -1 || dup (fd_s) == -1 || dup (fd_s) == -1) {
      perror ("dup");
      exit (EXIT_FAILURE);
    }
    close (fd_s);

#if 1
    if (setsid () == -1)
      perror ("warning: failed to setsid");
    if (ioctl (0, TIOCSCTTY, 0) == -1)
      perror ("warning: failed to TIOCSCTTY");
#endif

    /* Run the appliance.  This won't return until the user quits the
     * appliance.
     */
    guestfs_set_error_handler (g, NULL, NULL);
    r = guestfs_launch (g);

    /* launch() expects guestfsd to start. However, virt-rescue doesn't
     * run guestfsd, so this will always fail with ECHILD when the
     * appliance exits unexpectedly.
     */
    if (errno != ECHILD) {
      fprintf (stderr, "%s: %s\n", program_name, guestfs_last_error (g));
      guestfs_close (g);
      exit (EXIT_FAILURE);
    }

    guestfs_close (g);
    _exit (EXIT_SUCCESS);
  }

  /* Parent process continues ... */

  /* Close slave side of pty. */
  close (fd_s);

  /* Set raw mode. */
  r = tcgetattr (fd_s, &tsorig);
  tsnew = tsorig;
  cfmakeraw (&tsnew);
  tcsetattr (fd_s, TCSANOW, &tsnew);

  /* Send input and output to master side of pty. */
  r = multiplex (fd_m);
  tcsetattr (fd_s, TCSANOW, &tsorig); /* Restore cooked mode. */
  if (r == -1)
    exit (EXIT_FAILURE);

  if (waitpid (pid, &r, 0) == -1) {
    perror ("waitpid");
    exit (EXIT_FAILURE);
  }
  if (!WIFEXITED (r)) {
    /* abnormal child exit */
    fprintf (stderr, _("%s: unknown child exit status (%d)\n"),
             program_name, r);
    exit (EXIT_FAILURE);
  }
  else
    exit (WEXITSTATUS (r)); /* normal exit, return child process's status */
}

/* Naive and simple multiplex function. */
static int
multiplex (int fd_m)
{
  int r, eof_stdin = 0;
  fd_set rfds, wfds;
  char tobuf[BUFSIZ], frombuf[BUFSIZ]; /* to/from slave */
  size_t tosize = 0, fromsize = 0;
  ssize_t n;
  size_t count;
  long flags_0, flags_1, flags_fd_m;

  flags_0 = fcntl (0, F_GETFL);
  fcntl (0, F_SETFL, O_NONBLOCK | flags_0);
  flags_1 = fcntl (0, F_GETFL);
  fcntl (1, F_SETFL, O_NONBLOCK | flags_1);
  flags_fd_m = fcntl (0, F_GETFL);
  fcntl (fd_m, F_SETFL, O_NONBLOCK | flags_fd_m);

  for (;;) {
    FD_ZERO (&rfds);
    FD_ZERO (&wfds);

    /* Still space in to-buffer?  If so, we can read from the user. */
    if (!eof_stdin && tosize < BUFSIZ)
      FD_SET (0, &rfds);
    /* Still space in from-buffer?  If so, we can read from the slave. */
    if (fromsize < BUFSIZ)
      FD_SET (fd_m, &rfds);
    /* Content in to-buffer?  If so, we want to write to the slave. */
    if (tosize > 0)
      FD_SET (fd_m, &wfds);
    /* Content in from-buffer?  If so, we want to write to the user. */
    if (fromsize > 0)
      FD_SET (1, &wfds);

    r = select (fd_m+1, &rfds, &wfds, NULL, NULL);
    if (r == -1) {
      if (errno == EAGAIN || errno == EINTR)
        continue;
      perror ("select");
      return -1;
    }

    /* Input from user: Put it in the to-buffer. */
    if (FD_ISSET (0, &rfds)) {
      count = BUFSIZ - tosize;
      n = read (0, &tobuf[tosize], count);
      if (n == -1) {
        perror ("read");
        return -1;
      }
      if (n == 0) { /* stdin was closed */
        eof_stdin = 1;
        /* This is what telnetd does ... */
        tobuf[tosize] = '\004';
        tosize += 1;
      } else
        tosize += n;
    }

    /* Input from slave: Put it in the from-buffer. */
    if (FD_ISSET (fd_m, &rfds)) {
      count = BUFSIZ - fromsize;
      n = read (fd_m, &frombuf[fromsize], count);
      if (n == -1) {
        if (errno != EIO) /* EIO if slave process dies */
          perror ("read");
        break;
      }
      if (n == 0) /* slave closed the connection */
        break;
      fromsize += n;
    }

    /* Can write to user. */
    if (FD_ISSET (1, &wfds)) {
      n = write (1, frombuf, fromsize);
      if (n == -1) {
        perror ("write");
        return -1;
      }
      memmove (frombuf, &frombuf[n], BUFSIZ - n);
      fromsize -= n;
    }

    /* Can write to slave. */
    if (FD_ISSET (fd_m, &wfds)) {
      n = write (fd_m, tobuf, tosize);
      if (n == -1) {
        perror ("write");
        return -1;
      }
      memmove (tobuf, &tobuf[n], BUFSIZ - n);
      tosize -= n;
    }
  } /* for (;;) */

  /* We end up here when slave has closed the connection. */
  close (fd_m);

  /* Restore blocking behaviour. */
  fcntl (1, F_SETFL, flags_1);

  /* Last chance to write out any remaining data in the buffers, but
   * don't bother about errors.
   */
  ignore_value (write (1, frombuf, fromsize));

  return 0;
}
#endif
