/* virt-inspector
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
#include <errno.h>
#include <getopt.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include <libxml/xmlIO.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>

#include "guestfs.h"
#include "options.h"

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 1;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 1;
static const char *xpath = NULL;

static void output (char **roots);
static void output_roots (xmlTextWriterPtr xo, char **roots);
static void output_root (xmlTextWriterPtr xo, char *root);
static void output_mountpoints (xmlTextWriterPtr xo, char *root);
static void output_filesystems (xmlTextWriterPtr xo, char *root);
static void output_drive_mappings (xmlTextWriterPtr xo, char *root);
static void output_applications (xmlTextWriterPtr xo, char *root);
static void do_xpath (const char *query);

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             guestfs_int_program_name);
  else {
    fprintf (stdout,
           _("%s: display information about a virtual machine\n"
             "Copyright (C) 2010 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname file [file ...]\n"
             "  %s [--options] -a disk.img [-a disk.img ...] file [file ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --echo-keys          Don't turn off echo for passphrases\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  --keys-from-stdin    Read passphrases from stdin\n"
             "  -v|--verbose         Verbose messages\n"
             "  -V|--version         Display version and exit\n"
             "  -x                   Trace libguestfs API calls\n"
             "  --xpath query        Perform an XPath query\n"
             "For more information, see the manpage %s(1).\n"),
             guestfs_int_program_name, guestfs_int_program_name, guestfs_int_program_name,
             guestfs_int_program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:c:d:vVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "keys-from-stdin", 0, 0, 0 },
    { "long-options", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { "xpath", 1, 0, 0 },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int option_index;

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
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "xpath")) {
        xpath = optarg;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 guestfs_int_program_name, long_options[option_index].name, option_index);
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

  /* Old-style syntax?  There were no -a or -d options in the old
   * virt-inspector which is how we detect this.
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
        drv->a.filename = strdup (argv[optind]);
        if (!drv->a.filename) {
          perror ("strdup");
          exit (EXIT_FAILURE);
        }
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

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 1);
  assert (live == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  CHECK_OPTION_format_consumed;

  /* XPath is modal: no drives should be specified.  There must be
   * one extra parameter on the command line.
   */
  if (xpath) {
    if (drvs != NULL) {
      fprintf (stderr, _("%s: cannot use --xpath together with other options.\n"),
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }

    do_xpath (xpath);

    exit (EXIT_SUCCESS);
  }

  /* User must have specified some drives. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Add drives, inspect and mount.  Note that inspector is always true,
   * and there is no -m option.
   */
  add_drives (drvs, 'a');

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  /* NB. Can't call inspect_mount () here (ie. normal processing of
   * the -i option) because it can only handle a single root.  So we
   * use low-level APIs.
   */
  inspect_do_decrypt (g);

  {
    CLEANUP_FREE_STRING_LIST char **roots = guestfs_inspect_os (g);
    if (roots == NULL) {
      fprintf (stderr, _("%s: no operating system could be detected inside this disk image.\n\nThis may be because the file is not a disk image, or is not a virtual machine\nimage, or because the OS type is not understood by libguestfs.\n\nNOTE for Red Hat Enterprise Linux 6 users: for Windows guest support you must\ninstall the separate libguestfs-winsupport package.\n\nIf you feel this is an error, please file a bug report including as much\ninformation about the disk image as possible.\n"),
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }

    output (roots);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

#define XMLERROR(code,e) do {                                           \
    if ((e) == (code)) {                                                \
      fprintf (stderr, _("%s: XML write error at \"%s\": %m\n"),        \
               #e, guestfs_int_program_name);                                       \
      exit (EXIT_FAILURE);                                              \
    }                                                                   \
  } while (0)

static void
output (char **roots)
{
  xmlOutputBufferPtr ob = xmlOutputBufferCreateFd (1, NULL);
  if (ob == NULL) {
    fprintf (stderr,
             _("%s: xmlOutputBufferCreateFd: failed to open stdout\n"),
             guestfs_int_program_name);
    exit (EXIT_FAILURE);
  }

  /* 'ob' is freed when 'xo' is freed.. */
  CLEANUP_XMLFREETEXTWRITER xmlTextWriterPtr xo = xmlNewTextWriter (ob);
  if (xo == NULL) {
    fprintf (stderr,
             _("%s: xmlNewTextWriter: failed to create libxml2 writer\n"),
             guestfs_int_program_name);
    exit (EXIT_FAILURE);
  }

  /* Pretty-print the output. */
  XMLERROR (-1, xmlTextWriterSetIndent (xo, 1));
  XMLERROR (-1, xmlTextWriterSetIndentString (xo, BAD_CAST "  "));

  XMLERROR (-1, xmlTextWriterStartDocument (xo, NULL, NULL, NULL));
  output_roots (xo, roots);
  XMLERROR (-1, xmlTextWriterEndDocument (xo));
}

static void
output_roots (xmlTextWriterPtr xo, char **roots)
{
  size_t i;

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "operatingsystems"));
  for (i = 0; roots[i] != NULL; ++i)
    output_root (xo, roots[i]);
  XMLERROR (-1, xmlTextWriterEndElement (xo));
}

static void
output_root (xmlTextWriterPtr xo, char *root)
{
  char *str;
  int i, r;
  char buf[32];
  char *canonical_root;
  size_t size;

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "operatingsystem"));

  canonical_root = guestfs_canonical_device_name (g, root);
  if (canonical_root == NULL)
    exit (EXIT_FAILURE);
  XMLERROR (-1,
    xmlTextWriterWriteElement (xo, BAD_CAST "root", BAD_CAST canonical_root));
  free (canonical_root);

  str = guestfs_inspect_get_type (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "name", BAD_CAST str));
  free (str);

  str = guestfs_inspect_get_arch (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "arch", BAD_CAST str));
  free (str);

  str = guestfs_inspect_get_distro (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "distro", BAD_CAST str));
  free (str);

  str = guestfs_inspect_get_product_name (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "product_name", BAD_CAST str));
  free (str);

  str = guestfs_inspect_get_product_variant (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "product_variant", BAD_CAST str));
  free (str);

  i = guestfs_inspect_get_major_version (g, root);
  snprintf (buf, sizeof buf, "%d", i);
  XMLERROR (-1,
    xmlTextWriterWriteElement (xo, BAD_CAST "major_version", BAD_CAST buf));
  i = guestfs_inspect_get_minor_version (g, root);
  snprintf (buf, sizeof buf, "%d", i);
  XMLERROR (-1,
    xmlTextWriterWriteElement (xo, BAD_CAST "minor_version", BAD_CAST buf));

  str = guestfs_inspect_get_package_format (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "package_format", BAD_CAST str));
  free (str);

  str = guestfs_inspect_get_package_management (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "package_management",
                                 BAD_CAST str));
  free (str);

  /* inspect-get-windows-systemroot will fail with non-windows guests,
   * or if the systemroot could not be determined for a windows guest.
   * Disable error output around this call.
   */
  guestfs_push_error_handler (g, NULL, NULL);
  str = guestfs_inspect_get_windows_systemroot (g, root);
  if (str)
    XMLERROR (-1,
              xmlTextWriterWriteElement (xo, BAD_CAST "windows_systemroot",
                                         BAD_CAST str));
  free (str);
  str = guestfs_inspect_get_windows_current_control_set (g, root);
  if (str)
    XMLERROR (-1,
              xmlTextWriterWriteElement (xo, BAD_CAST "windows_current_control_set",
                                         BAD_CAST str));
  free (str);
  guestfs_pop_error_handler (g);

  str = guestfs_inspect_get_hostname (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "hostname",
                                 BAD_CAST str));
  free (str);

  str = guestfs_inspect_get_format (g, root);
  if (!str) exit (EXIT_FAILURE);
  if (STRNEQ (str, "unknown"))
    XMLERROR (-1,
      xmlTextWriterWriteElement (xo, BAD_CAST "format",
                                 BAD_CAST str));
  free (str);

  r = guestfs_inspect_is_live (g, root);
  if (r > 0) {
    XMLERROR (-1,
              xmlTextWriterStartElement (xo, BAD_CAST "live"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  r = guestfs_inspect_is_netinst (g, root);
  if (r > 0) {
    XMLERROR (-1,
              xmlTextWriterStartElement (xo, BAD_CAST "netinst"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  r = guestfs_inspect_is_multipart (g, root);
  if (r > 0) {
    XMLERROR (-1,
              xmlTextWriterStartElement (xo, BAD_CAST "multipart"));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  output_mountpoints (xo, root);

  output_filesystems (xo, root);

  output_drive_mappings (xo, root);

  /* We need to mount everything up in order to read out the list of
   * applications and the icon, ie. everything below this point.
   */
  inspect_mount_root (g, root);

  output_applications (xo, root);

  /* Don't return favicon.  RHEL 7 and Fedora have crappy 16x16
   * favicons in the base distro.
   */
  str = guestfs_inspect_get_icon (g, root, &size,
                                  GUESTFS_INSPECT_GET_ICON_FAVICON, 0,
                                  -1);
  if (!str) exit (EXIT_FAILURE);
  if (size > 0) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "icon"));
    XMLERROR (-1, xmlTextWriterWriteBase64 (xo, str, 0, size));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }
  /* Note we must free (str) even if size == 0, because that indicates
   * there was no icon.
   */
  free (str);

  /* Unmount (see inspect_mount_root above). */
  if (guestfs_umount_all (g) == -1)
    exit (EXIT_FAILURE);

  XMLERROR (-1, xmlTextWriterEndElement (xo));
}

static int
compare_keys (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;

  return strcmp (key1, key2);
}

static int
compare_keys_nocase (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;

  return strcasecmp (key1, key2);
}

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  int c;

  c = strlen (key1) - strlen (key2);
  if (c != 0)
    return c;

  return compare_keys (p1, p2);
}

static void
output_mountpoints (xmlTextWriterPtr xo, char *root)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **mountpoints =
    guestfs_inspect_get_mountpoints (g, root);
  if (mountpoints == NULL)
    exit (EXIT_FAILURE);

  /* Sort by key length, shortest key first, and then name, so the
   * output is stable.
   */
  qsort (mountpoints, guestfs_int_count_strings (mountpoints) / 2,
         2 * sizeof (char *),
         compare_keys_len);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "mountpoints"));

  for (i = 0; mountpoints[i] != NULL; i += 2) {
    CLEANUP_FREE char *p = guestfs_canonical_device_name (g, mountpoints[i+1]);
    if (!p)
      exit (EXIT_FAILURE);

    XMLERROR (-1,
              xmlTextWriterStartElement (xo, BAD_CAST "mountpoint"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "dev", BAD_CAST p));
    XMLERROR (-1,
              xmlTextWriterWriteString (xo, BAD_CAST mountpoints[i]));
    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  XMLERROR (-1, xmlTextWriterEndElement (xo));
}

static void
output_filesystems (xmlTextWriterPtr xo, char *root)
{
  char *str;
  size_t i;

  CLEANUP_FREE_STRING_LIST char **filesystems =
    guestfs_inspect_get_filesystems (g, root);
  if (filesystems == NULL)
    exit (EXIT_FAILURE);

  /* Sort by name so the output is stable. */
  qsort (filesystems, guestfs_int_count_strings (filesystems), sizeof (char *),
         compare_keys);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "filesystems"));

  for (i = 0; filesystems[i] != NULL; ++i) {
    str = guestfs_canonical_device_name (g, filesystems[i]);
    if (!str)
      exit (EXIT_FAILURE);

    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "filesystem"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "dev", BAD_CAST str));
    free (str);

    guestfs_push_error_handler (g, NULL, NULL);

    str = guestfs_vfs_type (g, filesystems[i]);
    if (str && str[0])
      XMLERROR (-1,
                xmlTextWriterWriteElement (xo, BAD_CAST "type",
                                           BAD_CAST str));
    free (str);

    str = guestfs_vfs_label (g, filesystems[i]);
    if (str && str[0])
      XMLERROR (-1,
                xmlTextWriterWriteElement (xo, BAD_CAST "label",
                                           BAD_CAST str));
    free (str);

    str = guestfs_vfs_uuid (g, filesystems[i]);
    if (str && str[0])
      XMLERROR (-1,
                xmlTextWriterWriteElement (xo, BAD_CAST "uuid",
                                           BAD_CAST str));
    free (str);

    guestfs_pop_error_handler (g);

    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  XMLERROR (-1, xmlTextWriterEndElement (xo));
}

static void
output_drive_mappings (xmlTextWriterPtr xo, char *root)
{
  CLEANUP_FREE_STRING_LIST char **drive_mappings = NULL;
  char *str;
  size_t i;

  guestfs_push_error_handler (g, NULL, NULL);
  drive_mappings = guestfs_inspect_get_drive_mappings (g, root);
  guestfs_pop_error_handler (g);
  if (drive_mappings == NULL)
    return;

  if (drive_mappings[0] == NULL)
    return;

  /* Sort by key. */
  qsort (drive_mappings,
         guestfs_int_count_strings (drive_mappings) / 2, 2 * sizeof (char *),
         compare_keys_nocase);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "drive_mappings"));

  for (i = 0; drive_mappings[i] != NULL; i += 2) {
    str = guestfs_canonical_device_name (g, drive_mappings[i+1]);
    if (!str)
      exit (EXIT_FAILURE);

    XMLERROR (-1,
              xmlTextWriterStartElement (xo, BAD_CAST "drive_mapping"));
    XMLERROR (-1,
              xmlTextWriterWriteAttribute (xo, BAD_CAST "name",
                                           BAD_CAST drive_mappings[i]));
    XMLERROR (-1,
              xmlTextWriterWriteString (xo, BAD_CAST str));
    XMLERROR (-1, xmlTextWriterEndElement (xo));

    free (str);
  }

  XMLERROR (-1, xmlTextWriterEndElement (xo));
}

static void
output_applications (xmlTextWriterPtr xo, char *root)
{
  size_t i;

  /* This returns an empty list if we simply couldn't determine the
   * applications, so if it returns NULL then it's a real error.
   */
  CLEANUP_FREE_APPLICATION2_LIST struct guestfs_application2_list *apps =
    guestfs_inspect_list_applications2 (g, root);
  if (apps == NULL)
    exit (EXIT_FAILURE);

  XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "applications"));

  for (i = 0; i < apps->len; ++i) {
    XMLERROR (-1, xmlTextWriterStartElement (xo, BAD_CAST "application"));

    assert (apps->val[i].app2_name && apps->val[i].app2_name[0]);
    XMLERROR (-1,
              xmlTextWriterWriteElement (xo, BAD_CAST "name",
                                         BAD_CAST apps->val[i].app2_name));

    if (apps->val[i].app2_display_name && apps->val[i].app2_display_name[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "display_name",
                                   BAD_CAST apps->val[i].app2_display_name));

    if (apps->val[i].app2_epoch != 0) {
      char buf[32];

      snprintf (buf, sizeof buf, "%d", apps->val[i].app2_epoch);

      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "epoch", BAD_CAST buf));
    }

    if (apps->val[i].app2_version && apps->val[i].app2_version[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "version",
                                   BAD_CAST apps->val[i].app2_version));
    if (apps->val[i].app2_release && apps->val[i].app2_release[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "release",
                                   BAD_CAST apps->val[i].app2_release));
    if (apps->val[i].app2_arch && apps->val[i].app2_arch[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "arch",
                                   BAD_CAST apps->val[i].app2_arch));
    if (apps->val[i].app2_install_path && apps->val[i].app2_install_path[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "install_path",
                                   BAD_CAST apps->val[i].app2_install_path));
    if (apps->val[i].app2_publisher && apps->val[i].app2_publisher[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "publisher",
                                   BAD_CAST apps->val[i].app2_publisher));
    if (apps->val[i].app2_url && apps->val[i].app2_url[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "url",
                                   BAD_CAST apps->val[i].app2_url));
    if (apps->val[i].app2_source_package && apps->val[i].app2_source_package[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "source_package",
                                   BAD_CAST apps->val[i].app2_source_package));
    if (apps->val[i].app2_summary && apps->val[i].app2_summary[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "summary",
                                   BAD_CAST apps->val[i].app2_summary));
    if (apps->val[i].app2_description && apps->val[i].app2_description[0])
      XMLERROR (-1,
        xmlTextWriterWriteElement (xo, BAD_CAST "description",
                                   BAD_CAST apps->val[i].app2_description));

    XMLERROR (-1, xmlTextWriterEndElement (xo));
  }

  XMLERROR (-1, xmlTextWriterEndElement (xo));
}

/* Run an XPath query on XML on stdin, print results to stdout. */
static void
do_xpath (const char *query)
{
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  xmlNodeSetPtr nodes;
  char *r;
  size_t i;
  xmlSaveCtxtPtr saveCtx;
  xmlNodePtr wrnode;

  doc = xmlReadFd (STDIN_FILENO, NULL, "utf8", 0);
  if (doc == NULL) {
    fprintf (stderr, _("%s: unable to parse XML from stdin\n"), guestfs_int_program_name);
    exit (EXIT_FAILURE);
  }

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL) {
    fprintf (stderr, _("%s: unable to create new XPath context\n"),
             guestfs_int_program_name);
    exit (EXIT_FAILURE);
  }

  xpathObj = xmlXPathEvalExpression (BAD_CAST query, xpathCtx);
  if (xpathObj == NULL) {
    fprintf (stderr, _("%s: unable to evaluate XPath expression\n"),
             guestfs_int_program_name);
    exit (EXIT_FAILURE);
  }

  switch (xpathObj->type) {
  case XPATH_NODESET:
    nodes = xpathObj->nodesetval;
    if (nodes == NULL)
      break;

    saveCtx = xmlSaveToFd (STDOUT_FILENO, NULL, XML_SAVE_NO_DECL);
    if (saveCtx == NULL) {
      fprintf (stderr, _("%s: xmlSaveToFd failed\n"), guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }

    for (i = 0; i < (size_t) nodes->nodeNr; ++i) {
      CLEANUP_XMLFREEDOC xmlDocPtr wrdoc = xmlNewDoc (BAD_CAST "1.0");
      if (wrdoc == NULL) {
        fprintf (stderr, _("%s: xmlNewDoc failed\n"), guestfs_int_program_name);
        exit (EXIT_FAILURE);
      }
      wrnode = xmlCopyNode (nodes->nodeTab[i], 1);
      if (wrnode == NULL) {
        fprintf (stderr, _("%s: xmlCopyNode failed\n"), guestfs_int_program_name);
        exit (EXIT_FAILURE);
      }

      xmlDocSetRootElement (wrdoc, wrnode);

      if (xmlSaveDoc (saveCtx, wrdoc) == -1) {
        fprintf (stderr, _("%s: xmlSaveDoc failed\n"), guestfs_int_program_name);
        exit (EXIT_FAILURE);
      }
    }

    xmlSaveClose (saveCtx);

    break;

  case XPATH_STRING:
    r = (char *) xpathObj->stringval;
    printf ("%s", r);
    i = strlen (r);
    if (i > 0 && r[i-1] != '\n')
      printf ("\n");
    break;

  case XPATH_UNDEFINED: /* grrrrr ... switch-enum is a useless warning */
  case XPATH_BOOLEAN:
  case XPATH_NUMBER:
  case XPATH_POINT:
  case XPATH_RANGE:
  case XPATH_LOCATIONSET:
  case XPATH_USERS:
  case XPATH_XSLT_TREE:
  default:
    r = (char *) xmlXPathCastToString (xpathObj);
    printf ("%s\n", r);
    free (r);
  }
}
