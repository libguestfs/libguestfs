/* virt-log
 * Copyright (C) 2010-2014 Red Hat Inc.
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
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>
#include <syslog.h>
#include <time.h>
#include <sys/types.h>
#include <sys/wait.h>

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

#define JOURNAL_DIR "/var/log/journal"

static int do_log (void);
static int do_log_journal (void);
static int do_log_text_file (const char *filename);
static int do_log_windows_evtx (void);

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             guestfs_int_program_name);
  else {
    fprintf (stdout,
           _("%s: display log files in a virtual machine\n"
             "Copyright (C) 2010-2014 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname\n"
             "  %s [--options] -a disk.img [-a disk.img ...]\n"
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
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int r;
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

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 1);
  assert (live == 0);

  /* User must not specify more arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  CHECK_OPTION_format_consumed;

  /* User must have specified some drives. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Add drives, inspect and mount.  Note that inspector is always true,
   * and there is no -m option.
   */
  add_drives (drvs, 'a');

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  inspect_mount ();

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  r = do_log ();

  guestfs_close (g);

  exit (r == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

static int
do_log (void)
{
  CLEANUP_FREE_STRING_LIST char **roots = NULL;
  char *root;
  CLEANUP_FREE char *type = NULL;
  CLEANUP_FREE_STRING_LIST char **journal_files = NULL;

  /* Get root mountpoint.  fish/inspect.c guarantees the assertions
   * below.
   */
  roots = guestfs_inspect_get_roots (g);
  assert (roots);
  assert (roots[0] != NULL);
  assert (roots[1] == NULL);
  root = roots[0];

  type = guestfs_inspect_get_type (g, root);
  if (!type)
    return -1;

  /* Windows needs special handling. */
  if (STREQ (type, "windows")) {
    if (guestfs_inspect_get_major_version (g, root) >= 6)
      return do_log_windows_evtx ();

    fprintf (stderr,
             _("%s: Windows Event Log for pre-Vista guests is not supported.\n"),
             guestfs_int_program_name);
    return -1;
  }

  /* systemd journal? */
  guestfs_push_error_handler (g, NULL, NULL);
  journal_files = guestfs_ls (g, JOURNAL_DIR);
  guestfs_pop_error_handler (g);
  if (STREQ (type, "linux") &&
      journal_files != NULL && journal_files[0] != NULL)
    return do_log_journal ();

  /* Regular /var/log text files with different names. */
  if (STRNEQ (type, "windows")) {
    const char *logfiles[] = { "/var/log/syslog", "/var/log/messages", NULL };
    size_t i;

    for (i = 0; logfiles[i] != NULL; ++i) {
      if (guestfs_is_file_opts (g, logfiles[i],
                                GUESTFS_IS_FILE_OPTS_FOLLOWSYMLINKS, 1,
                                -1) == 1)
        return do_log_text_file (logfiles[i]);
    }
  }

  /* Otherwise, there are no log files.  Hmm, is this right? XXX */
  return 0;
}

/* Find the value of the named field from the list of attributes.  If
 * not found, returns NULL (not an error).  If found, returns a
 * pointer to the field, and the length of the field.  NOTE: The field
 * is NOT \0-terminated, so you have to print it using "%.*s".
 *
 * There may be multiple fields with the same name.  In this case, the
 * function returns the first entry.
 */
static const char *
get_journal_field (const struct guestfs_xattr_list *xattrs, const char *name,
                   size_t *len_rtn)
{
  uint32_t i;

  for (i = 0; i < xattrs->len; ++i) {
    if (STREQ (name, xattrs->val[i].attrname)) {
      *len_rtn = xattrs->val[i].attrval_len;
      return xattrs->val[i].attrval;
    }
  }

  return NULL;                  /* not found */
}

static const char *const log_level_table[] = {
  [LOG_EMERG] = "emerg",
  [LOG_ALERT] = "alert",
  [LOG_CRIT] = "crit",
  [LOG_ERR] = "err",
  [LOG_WARNING] = "warning",
  [LOG_NOTICE] = "notice",
  [LOG_INFO] = "info",
  [LOG_DEBUG] = "debug"
};

static int
do_log_journal (void)
{
  int r;
  unsigned errors = 0;

  if (guestfs_journal_open (g, JOURNAL_DIR) == -1)
    return -1;

  while ((r = guestfs_journal_next (g)) > 0) {
    CLEANUP_FREE_XATTR_LIST struct guestfs_xattr_list *xattrs = NULL;
    const char *priority_str, *identifier, *comm, *pid, *message;
    size_t priority_len, identifier_len, comm_len, pid_len, message_len;
    int priority = LOG_INFO;
    int64_t ts;

    /* The question is what fields to display.  We should probably
     * make this configurable, but for now use the "short" format from
     * journalctl.  (XXX)
     */

    xattrs = guestfs_journal_get (g);
    if (xattrs == NULL)
      return -1;

    ts = guestfs_journal_get_realtime_usec (g); /* error checked below */

    priority_str = get_journal_field (xattrs, "PRIORITY", &priority_len);
    //hostname = get_journal_field (xattrs, "_HOSTNAME", &hostname_len);
    identifier = get_journal_field (xattrs, "SYSLOG_IDENTIFIER",
                                    &identifier_len);
    comm = get_journal_field (xattrs, "_COMM", &comm_len);
    pid = get_journal_field (xattrs, "_PID", &pid_len);
    message = get_journal_field (xattrs, "MESSAGE", &message_len);

    /* Timestamp. */
    if (ts >= 0) {
      char buf[64];
      time_t t = ts / 1000000;
      struct tm tm;

      if (strftime (buf, sizeof buf, "%b %d %H:%M:%S",
                    localtime_r (&t, &tm)) <= 0) {
        fprintf (stderr, _("%s: could not format journal entry timestamp\n"),
                 guestfs_int_program_name);
        errors++;
        continue;
      }
      fputs (buf, stdout);
    }

    /* Hostname. */
    /* We don't print this because it is assumed each line from the
     * guest will have the same hostname.  (XXX)
     */
    //if (hostname)
    //  printf (" %.*s", (int) hostname_len, hostname);

    /* Identifier. */
    if (identifier)
      printf (" %.*s", (int) identifier_len, identifier);
    else if (comm)
      printf (" %.*s", (int) comm_len, comm);

    /* PID */
    if (pid)
      printf ("[%.*s]", (int) pid_len, pid);

    /* Log level. */
    if (priority_str && *priority_str >= '0' && *priority_str <= '7')
      priority = *priority_str - '0';

    printf (" %s:", log_level_table[priority]);

    /* Message. */
    if (message)
      printf (" %.*s", (int) message_len, message);

    printf ("\n");
  }
  if (r == -1)                  /* error from guestfs_journal_next */
    return -1;

  if (guestfs_journal_close (g) == -1)
    return -1;

  return errors > 0 ? -1 : 0;
}

static int
do_log_text_file (const char *filename)
{
  return guestfs_download (g, filename, "/dev/stdout");
}

/* For Windows >= Vista, if evtxdump.py is installed then we can
 * use it to dump the System.evtx log.
 */
static int
do_log_windows_evtx (void)
{
  CLEANUP_FREE char *filename = NULL;
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g);
  CLEANUP_UNLINK_FREE char *localfile = NULL;
  CLEANUP_FREE char *cmd = NULL;
  char dev_fd[64];
  int fd, status;

  if (system ("evtxdump.py -h >/dev/null 2>&1") != 0) {
    fprintf (stderr, _("%s: you need to install 'evtxdump.py' (from the python-evtx package)\n"
                       "in order to parse Windows Event Logs.  If you cannot install this, then\n"
                       "use virt-copy-out(1) to copy the contents of /Windows/System32/winevt/Logs\n"
                       "from this guest, and examine in a binary file viewer.\n"),
             guestfs_int_program_name);
    return -1;
  }

  /* Check if System.evtx exists.  XXX Allow the filename to be
   * configurable, since there are many logs.
   */
  filename = guestfs_case_sensitive_path (g, "/Windows/System32/winevt/Logs/System.evtx");
  if (filename == NULL)
    return -1;

  /* Note that guestfs_case_sensitive_path does NOT check for existence. */
  if (guestfs_is_file_opts (g, filename,
                            GUESTFS_IS_FILE_OPTS_FOLLOWSYMLINKS, 1,
                            -1) <= 0) {
    fprintf (stderr, _("%s: Windows Event Log file (%s) not found\n"),
             guestfs_int_program_name, filename);
    return -1;
  }

  /* Download the file to a temporary.  Python-evtx wants to mmap
   * the file so we cannot use a pipe.
   */
  if (asprintf (&localfile, "%s/virtlogXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    return -1;
  }
  if ((fd = mkstemp (localfile)) == -1) {
    perror ("mkstemp");
    return -1;
  }

  snprintf (dev_fd, sizeof dev_fd, "/dev/fd/%d", fd);

  if (guestfs_download (g, filename, dev_fd) == -1)
    return -1;
  close (fd);

  /* This should be safe as long as $TMPDIR is not set to something wild. */
  if (asprintf (&cmd, "evtxdump.py '%s'", localfile) == -1) {
    perror ("asprintf");
    return -1;
  }

  status = system (cmd);
  if (status) {
    char buf[256];
    fprintf (stderr, "%s: %s\n",
             guestfs_int_program_name,
             guestfs_int_exit_status_to_string (status, "evtxdump.py",
                                              buf, sizeof buf));
    return -1;
  }

  return 0;
}
