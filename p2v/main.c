/* virt-p2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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
#include <error.h>
#include <dirent.h>
#include <locale.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/stat.h>

#if MAJOR_IN_MKDEV
#include <sys/mkdev.h>
#elif MAJOR_IN_SYSMACROS
#include <sys/sysmacros.h>
/* else it's in sys/types.h, included above */
#endif

/* errors in <gtk.h> */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wstrict-prototypes"
#if defined(__GNUC__) && __GNUC__ >= 6 /* gcc >= 6 */
#pragma GCC diagnostic ignored "-Wshift-overflow"
#endif
#include <gtk/gtk.h>
#pragma GCC diagnostic pop

#include "ignore-value.h"
#include "getprogname.h"
#include "p2v.h"

char **all_disks;
char **all_removable;
char **all_interfaces;
int is_iso_environment = 0;
int feature_colours_option = 0;
int force_colour = 0;

static const char *test_disk = NULL;

static void udevadm_settle (void);
static void set_config_defaults (struct config *config);
static void find_all_disks (void);
static void find_all_interfaces (void);
static int cpuinfo_flags (void);

enum { HELP_OPTION = CHAR_MAX + 1 };
static const char options[] = "Vv";
static const struct option long_options[] = {
  { "help", 0, 0, HELP_OPTION },
  { "cmdline", 1, 0, 0 },
  { "color", 0, 0, 0 },
  { "colors", 0, 0, 0 },
  { "colour", 0, 0, 0 },
  { "colours", 0, 0, 0 },
  { "iso", 0, 0, 0 },
  { "long-options", 0, 0, 0 },
  { "short-options", 0, 0, 0 },
  { "test-disk", 1, 0, 0 },
  { "verbose", 0, 0, 'v' },
  { "version", 0, 0, 'V' },
  { 0, 0, 0, 0 }
};

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: Convert a physical machine to use KVM\n"
              "Copyright (C) 2009-2016 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options]\n"
              "Options:\n"
              "  --help                 Display brief help\n"
              " --cmdline=CMDLINE       Used to debug command line parsing\n"
              " --colors|--colours      Use ANSI colour sequences even if not tty\n"
              " --iso                   Running in the ISO environment\n"
              " --test-disk=DISK.IMG    For testing, use disk as /dev/sda\n"
              "  -v|--verbose           Verbose messages\n"
              "  -V|--version           Display version and exit\n"
              "For more information, see the manpage %s(1).\n"),
            getprogname (), getprogname (),
            getprogname ());
  }
  exit (status);
}

/* XXX Copied from fish/options.c. */
static void
display_short_options (const char *format)
{
  while (*format) {
    if (*format != ':')
      printf ("-%c\n", *format);
    ++format;
  }
  exit (EXIT_SUCCESS);
}

static void
display_long_options (const struct option *long_options)
{
  while (long_options->name) {
    if (STRNEQ (long_options->name, "long-options") && STRNEQ (long_options->name, "short-options"))
      printf ("--%s\n", long_options->name);
    long_options++;
  }
  exit (EXIT_SUCCESS);
}

int
main (int argc, char *argv[])
{
  gboolean gui_possible;
  int c;
  int option_index;
  char **cmdline = NULL;
  int cmdline_source = 0;
  struct config *config = new_config ();

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  /* There is some raciness between slow devices being discovered by
   * the kernel and udev and virt-p2v running.  This is a partial
   * workaround, but a real fix involves handling hotplug events
   * (possible in GUI mode, not easy in kernel mode).
   */
  udevadm_settle ();

  gui_possible = gtk_init_check (&argc, &argv);

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
      else if (STREQ (long_options[option_index].name, "cmdline")) {
        cmdline = parse_cmdline_string (optarg);
        cmdline_source = CMDLINE_SOURCE_COMMAND_LINE;
      }
      else if (STREQ (long_options[option_index].name, "color") ||
               STREQ (long_options[option_index].name, "colour") ||
               STREQ (long_options[option_index].name, "colors") ||
               STREQ (long_options[option_index].name, "colours")) {
        force_colour = 1;
      }
      else if (STREQ (long_options[option_index].name, "iso")) {
        is_iso_environment = 1;
      }
      else if (STREQ (long_options[option_index].name, "test-disk")) {
        if (test_disk != NULL)
          error (EXIT_FAILURE, 0,
                 _("only a single --test-disk option can be used"));
        if (optarg[0] != '/')
          error (EXIT_FAILURE, 0,
                 _("--test-disk must be an absolute path"));
        test_disk = optarg;
      }
      else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
      break;

    case 'v':
      /* This option does nothing since 1.33.41.  Verbose is always
       * enabled.
       */
      break;

    case 'V':
      printf ("%s %s\n", getprogname (), PACKAGE_VERSION_FULL);
      exit (EXIT_SUCCESS);

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (optind != argc) {
    fprintf (stderr, _("%s: unused arguments on the command line\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  set_config_defaults (config);

  /* Parse /proc/cmdline (if it exists) or use the --cmdline parameter
   * to initialize the configuration.  This allows defaults to be pass
   * using the kernel command line, with additional GUI configuration
   * later.
   */
  if (cmdline == NULL) {
    cmdline = parse_proc_cmdline ();
    if (cmdline != NULL)
      cmdline_source = CMDLINE_SOURCE_PROC_CMDLINE;
  }

  if (cmdline)
    update_config_from_kernel_cmdline (config, cmdline);

  /* If p2v.server exists, then we use the non-interactive kernel
   * conversion.  Otherwise we run the GUI.
   */
  if (config->server != NULL)
    kernel_conversion (config, cmdline, cmdline_source);
  else {
    if (!gui_possible)
      error (EXIT_FAILURE, 0,
             _("gtk_init_check returned false, indicating that\n"
               "a GUI is not possible on this host.  Check X11, $DISPLAY etc."));
    gui_conversion (config);
  }

  guestfs_int_free_string_list (cmdline);

  exit (EXIT_SUCCESS);
}

static void
udevadm_settle (void)
{
  ignore_value (system ("udevadm settle"));
}

static void
set_config_defaults (struct config *config)
{
  long i;
  char hostname[257];
  int flags;

  /* Default guest name is derived from the source hostname.  If we
   * assume that the p2v ISO gets its IP address and hostname from
   * DHCP, then there is at better than average chance that
   * gethostname will return the real hostname here.  It's better than
   * trying to fish around in the guest filesystem anyway.
   */
  if (gethostname (hostname, sizeof hostname) == -1) {
    perror ("gethostname");
    /* Generate a simple random name. */
    if (guestfs_int_random_string (hostname, 8) == -1)
      error (EXIT_FAILURE, errno, "guestfs_int_random_string");
  } else {
    char *p;

    /* If the hostname is an FQDN, truncate before the first dot. */
    p = strchr (hostname, '.');
    if (p && p > hostname)
      *p = '\0';
  }
  config->guestname = strdup (hostname);

  /* Defaults for #vcpus and memory are taken from the physical machine. */
  i = sysconf (_SC_NPROCESSORS_ONLN);
  if (i == -1) {
    perror ("sysconf: _SC_NPROCESSORS_ONLN");
    config->vcpus = 1;
  }
  else if (i == 0)
    config->vcpus = 1;
  else
    config->vcpus = i;

  i = sysconf (_SC_PHYS_PAGES);
  if (i == -1) {
    perror ("sysconf: _SC_PHYS_PAGES");
    config->memory = 1024 * 1024 * 1024;
  }
  else
    config->memory = i;

  i  = sysconf (_SC_PAGESIZE);
  if (i == -1) {
    perror ("sysconf: _SC_PAGESIZE");
    config->memory *= 4096;
  }
  else
    config->memory *= i;

  /* Round up the default memory to a power of 2, since the kernel
   * memory is not included in the total physical pages returned
   * above.
   * http://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2
   */
  config->memory--;
  config->memory |= config->memory >> 1;
  config->memory |= config->memory >> 2;
  config->memory |= config->memory >> 4;
  config->memory |= config->memory >> 8;
  config->memory |= config->memory >> 16;
  config->memory |= config->memory >> 32;
  config->memory++;

  flags = cpuinfo_flags ();
  if (flags >= 0)
    config->flags = flags;
  else
    config->flags = 0;

  /* Find all block devices in the system. */
  if (!test_disk)
    find_all_disks ();
  else {
    /* For testing and debugging purposes, you can use
     * --test-disk=/path/to/disk.img
     */
    all_disks = malloc (2 * sizeof (char *));
    if (all_disks == NULL)
      error (EXIT_FAILURE, errno, "realloc");
    all_disks[0] = strdup (test_disk);
    if (all_disks[0] == NULL)
      error (EXIT_FAILURE, errno, "strdup");
    all_disks[1] = NULL;
  }
  if (all_disks)
    config->disks = guestfs_int_copy_string_list (all_disks);

  /* Find all removable devices in the system. */
  if (all_removable)
    config->removable = guestfs_int_copy_string_list (all_removable);

  /* Find all network interfaces in the system. */
  find_all_interfaces ();
  if (all_interfaces)
    config->interfaces = guestfs_int_copy_string_list (all_interfaces);

  /* Default output drops the guest onto /var/tmp on the conversion
   * server, a hopefully safe default.
   */
  config->output = strdup ("local");
  config->output_storage = strdup ("/var/tmp");
}

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcmp (*p1, *p2);
}

/**
 * Get parent device of a partition.
 *
 * Returns C<0> if no parent device could be found.
 */
static dev_t
partition_parent (dev_t part_dev)
{
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *path = NULL, *content = NULL;
  size_t len = 0;
  unsigned parent_major, parent_minor;

  if (asprintf (&path, "/sys/dev/block/%ju:%ju/../dev",
                (uintmax_t) major (part_dev),
                (uintmax_t) minor (part_dev)) == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  fp = fopen (path, "r");
  if (fp == NULL)
    return 0;

  if (getline (&content, &len, fp) == -1)
    error (EXIT_FAILURE, errno, "getline");

  if (sscanf (content, "%u:%u", &parent_major, &parent_minor) != 2)
    return 0;

  return makedev (parent_major, parent_minor);
}

/**
 * Return true if the named device (eg. C<dev == "sda">) contains the
 * root filesystem.  C<root_device> is the major:minor of the root
 * filesystem (eg. C<8:1> if the root filesystem was F</dev/sda1>).
 *
 * This doesn't work for LVs and so on.  However we only really care
 * if this test works on the P2V ISO where the root device is a
 * regular partition.
 */
static int
device_contains (const char *dev, dev_t root_device)
{
  struct stat statbuf;
  CLEANUP_FREE char *dev_name = NULL;
  dev_t root_device_parent;

  if (asprintf (&dev_name, "/dev/%s", dev) == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  if (stat (dev_name, &statbuf) == -1)
    return 0;

  /* See if dev is the root_device. */
  if (statbuf.st_rdev == root_device)
    return 1;

  /* See if dev is the parent device of the root_device. */
  root_device_parent = partition_parent (root_device);
  if (root_device_parent == 0)
    return 0;
  if (statbuf.st_rdev == root_device_parent)
    return 1;

  return 0;
}

/**
 * Enumerate all disks in F</sys/block> and add them to the global
 * C<all_disks> and C<all_removable> arrays.
 */
static void
find_all_disks (void)
{
  DIR *dir;
  struct dirent *d;
  size_t nr_disks = 0, nr_removable = 0;
  dev_t root_device = 0;
  struct stat statbuf;

  if (stat ("/", &statbuf) == 0)
    root_device = statbuf.st_dev;

  /* The default list of disks is everything in /sys/block which
   * matches the common patterns for disk names.
   */
  dir = opendir ("/sys/block");
  if (!dir)
    error (EXIT_FAILURE, errno, "opendir");

  for (;;) {
    errno = 0;
    d = readdir (dir);
    if (!d) break;

    if (STRPREFIX (d->d_name, "cciss!") ||
        STRPREFIX (d->d_name, "hd") ||
        STRPREFIX (d->d_name, "sd") ||
        STRPREFIX (d->d_name, "ubd") ||
        STRPREFIX (d->d_name, "vd")) {
      char *p;

      /* Skip the device containing the root filesystem. */
      if (device_contains (d->d_name, root_device))
        continue;

      nr_disks++;
      all_disks = realloc (all_disks, sizeof (char *) * (nr_disks + 1));
      if (!all_disks)
        error (EXIT_FAILURE, errno, "realloc");

      all_disks[nr_disks-1] = strdup (d->d_name);

      /* cciss device /dev/cciss/c0d0 will be /sys/block/cciss!c0d0 */
      p = strchr (all_disks[nr_disks-1], '!');
      if (p) *p = '/';

      all_disks[nr_disks] = NULL;
    }
    else if (STRPREFIX (d->d_name, "sr")) {
      nr_removable++;
      all_removable = realloc (all_removable,
                               sizeof (char *) * (nr_removable + 1));
      if (!all_removable)
        error (EXIT_FAILURE, errno, "realloc");
      all_removable[nr_removable-1] = strdup (d->d_name);
      all_removable[nr_removable] = NULL;
    }
  }

  /* Check readdir didn't fail */
  if (errno != 0)
    error (EXIT_FAILURE, errno, "readdir: %s", "/sys/block");

  /* Close the directory handle */
  if (closedir (dir) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", "/sys/block");

  if (all_disks)
    qsort (all_disks, nr_disks, sizeof (char *), compare);
  if (all_removable)
    qsort (all_removable, nr_removable, sizeof (char *), compare);
}

/**
 * Enumerate all network interfaces in F</sys/class/net> and add them
 * to the global C<all_interfaces> array.
 */
static void
find_all_interfaces (void)
{
  DIR *dir;
  struct dirent *d;
  size_t nr_interfaces = 0;

  /* The default list of network interfaces is everything in
   * /sys/class/net which matches some common patterns.
   */
  dir = opendir ("/sys/class/net");
  if (!dir)
    error (EXIT_FAILURE, errno, "opendir: %s", "/sys/class/net");

  for (;;) {
    errno = 0;
    d = readdir (dir);
    if (!d) break;

    /* For systemd predictable names, see:
     * http://cgit.freedesktop.org/systemd/systemd/tree/src/udev/udev-builtin-net_id.c#n20
     * biosdevname is also a possibility here.
     * Ignore PPP, SLIP, WWAN, bridges, etc.
     */
    if (STRPREFIX (d->d_name, "em") ||
        STRPREFIX (d->d_name, "en") ||
        STRPREFIX (d->d_name, "eth") ||
        STRPREFIX (d->d_name, "wl")) {
      nr_interfaces++;
      all_interfaces =
        realloc (all_interfaces, sizeof (char *) * (nr_interfaces + 1));
      if (!all_interfaces)
        error (EXIT_FAILURE, errno, "realloc");
      all_interfaces[nr_interfaces-1] = strdup (d->d_name);
      all_interfaces[nr_interfaces] = NULL;
    }
  }

  /* Check readdir didn't fail */
  if (errno != 0)
    error (EXIT_FAILURE, errno, "readdir: %s", "/sys/class/net");

  /* Close the directory handle */
  if (closedir (dir) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", "/sys/class/net");

  if (all_interfaces)
    qsort (all_interfaces, nr_interfaces, sizeof (char *), compare);
}

/**
 * Read the list of flags from F</proc/cpuinfo>.
 */
static int
cpuinfo_flags (void)
{
  const char *cmd;
  CLEANUP_PCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *flag = NULL;
  ssize_t len;
  size_t buflen = 0;
  int ret = 0;

  /* Get the flags, one per line. */
  cmd = "< /proc/cpuinfo "
#if defined(__arm__)
    "grep ^Features"
#else
    "grep ^flags"
#endif
    " | awk '{ for (i = 3; i <= NF; ++i) { print $i }; exit }'";

  fp = popen (cmd, "re");
  if (fp == NULL) {
    perror ("/proc/cpuinfo");
    return -1;
  }

  while (errno = 0, (len = getline (&flag, &buflen, fp)) != -1) {
    if (len > 0 && flag[len-1] == '\n')
      flag[len-1] = '\0';

    if (STREQ (flag, "acpi"))
      ret |= FLAG_ACPI;
    else if (STREQ (flag, "apic"))
      ret |= FLAG_APIC;
    else if (STREQ (flag, "pae"))
      ret |= FLAG_PAE;
  }

  if (errno) {
    perror ("getline");
    return -1;
  }

  return ret;
}
