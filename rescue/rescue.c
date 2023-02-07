/* virt-rescue
 * Copyright (C) 2010-2023 Red Hat Inc.
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
#include <error.h>
#include <signal.h>
#include <termios.h>
#include <poll.h>
#include <locale.h>
#include <limits.h>
#include <assert.h>
#include <libintl.h>

#include "full-write.h"
#include "getprogname.h"
#include "ignore-value.h"
#include "nonblocking.h"

#include "guestfs.h"
#include "guestfs-utils.h"

#include "windows.h"
#include "options.h"
#include "display-options.h"

#include "rescue.h"

static void log_message_callback (guestfs_h *g, void *opaque, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);
static void do_rescue (int sock);
static void raw_tty (void);
static void restore_tty (void);
static void tstp_handler (int sig);
static void cont_handler (int sig);
static void add_scratch_disks (int n, struct drv **drvs);

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 0;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;
int in_guestfish = 0;
int in_virt_rescue = 1;
int escape_key = '\x1d';        /* ^] */

/* Old terminal settings. */
static struct termios old_termios;

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: Run a rescue shell on a virtual machine\n"
              "Copyright (C) 2009-2023 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] -d domname\n"
              "  %s [--options] -a disk.img [-a disk.img ...]\n"
              "Options:\n"
              "  -a|--add image       Add image\n"
              "  --append kernelopts  Append kernel options\n"
              "  --blocksize[=512|4096]\n"
              "                       Set sector size of the disk for -a option\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  -e ^x|none           Set or disable escape key (default ^])\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  --help               Display brief help\n"
              "  -i|--inspector       Automatically mount filesystems\n"
              "  -m|--mount dev[:mnt[:opts[:fstype]] Mount dev on mnt (if omitted, /)\n"
              "  --memsize MB         Set memory size in megabytes\n"
              "  --network            Enable network\n"
              "  -r|--ro              Access read-only\n"
              "  --scratch[=N]        Add scratch disk(s)\n"
              "  --selinux            For backwards compat only, does nothing\n"
              "  --smp N              Enable SMP with N >= 2 virtual CPUs\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -w|--rw              Mount read-write\n"
              "  -x                   Trace libguestfs API calls\n"
              "For more information, see the manpage %s(1).\n"),
            getprogname (), getprogname (),
            getprogname (), getprogname ());
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  parse_config ();

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char options[] = "a:c:d:e:im:rvVwx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "append", 1, 0, 0 },
    { "blocksize", 2, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "inspector", 0, 0, 'i' },
    { "long-options", 0, 0, 0 },
    { "mount", 1, 0, 'm' },
    { "memsize", 1, 0, 0 },
    { "network", 0, 0, 0 },
    { "ro", 0, 0, 'r' },
    { "rw", 0, 0, 'w' },
    { "scratch", 2, 0, 0 },
    { "selinux", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "smp", 1, 0, 0 },
    { "suggest", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  struct mp *mps = NULL;
  struct mp *mp;
  char *p;
  const char *format = NULL;
  bool format_consumed = true;
  int blocksize = 0;
  bool blocksize_consumed = true;
  int c;
  int option_index;
  int network = 0;
  const char *append = NULL;
  int memsize = 0, m;
  int smp = 0;
  int suggest = 0;
  char *append_full;
  int sock;
  struct key_store *ks = NULL;

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "selinux")) {
        /* nothing */
      } else if (STREQ (long_options[option_index].name, "append")) {
        append = optarg;
      } else if (STREQ (long_options[option_index].name, "network")) {
        network = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "blocksize")) {
        OPTION_blocksize;
      } else if (STREQ (long_options[option_index].name, "smp")) {
        if (sscanf (optarg, "%d", &smp) != 1)
          error (EXIT_FAILURE, 0,
                 _("could not parse --smp parameter ‘%s’"), optarg);
        if (smp < 1)
          error (EXIT_FAILURE, 0,
                 _("--smp parameter ‘%s’ should be >= 1"), optarg);
      } else if (STREQ (long_options[option_index].name, "suggest")) {
        suggest = 1;
      } else if (STREQ (long_options[option_index].name, "scratch")) {
        if (!optarg || STREQ (optarg, ""))
          add_scratch_disks (1, &drvs);
        else {
          int n;
          if (sscanf (optarg, "%d", &n) != 1)
            error (EXIT_FAILURE, 0,
                   _("could not parse --scratch parameter ‘%s’"), optarg);
          if (n < 1)
            error (EXIT_FAILURE, 0,
                   _("--scratch parameter ‘%s’ should be >= 1"), optarg);
          add_scratch_disks (n, &drvs);
        }
      } else if (STREQ (long_options[option_index].name, "memsize")) {
        if (sscanf (optarg, "%d", &memsize) != 1)
          error (EXIT_FAILURE, 0,
                 _("could not parse memory size ‘%s’"), optarg);
      } else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
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

    case 'e':
      escape_key = parse_escape_key (optarg);
      if (escape_key == -1)
        error (EXIT_FAILURE, 0, _("unrecognized escape key: %s"), optarg);
      break;

    case 'i':
      OPTION_i;
      break;

    case 'm':
      /* For backwards compatibility with virt-rescue <= 1.36, we
       * must handle -m <number> as a synonym for --memsize.
       */
      if (sscanf (optarg, "%d", &m) == 1)
        memsize = m;
      else {
        OPTION_m;
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
        if (!drv)
          error (EXIT_FAILURE, errno, "calloc");
        drv->type = drv_a;
        drv->a.filename = strdup (argv[optind]);
        if (!drv->a.filename)
          error (EXIT_FAILURE, errno, "strdup");
        drv->next = drvs;
        drvs = drv;
      } else {                  /* simulate -d option */
        drv = calloc (1, sizeof (struct drv));
        if (!drv)
          error (EXIT_FAILURE, errno, "calloc");
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
  assert (keys_from_stdin == 0);
  assert (echo_keys == 0);
  assert (live == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc) {
    fprintf (stderr, _("%s: error: extra argument ‘%s’ on command line.\n"
             "Make sure to specify the argument for --format or --scratch "
             "like '--format=%s'.\n"),
             getprogname (), argv[optind], argv[optind]);
    usage (EXIT_FAILURE);
  }

  CHECK_OPTION_format_consumed;
  CHECK_OPTION_blocksize_consumed;

  /* User must have specified some drives. */
  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a or -d option.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  /* Set other features. */
  if (memsize > 0)
    if (guestfs_set_memsize (g, memsize) == -1)
      exit (EXIT_FAILURE);
  if (network)
    if (guestfs_set_network (g, 1) == -1)
      exit (EXIT_FAILURE);
  if (smp >= 1)
    if (guestfs_set_smp (g, smp) == -1)
      exit (EXIT_FAILURE);

  /* Kernel command line must include guestfs_rescue=1 (see
   * appliance/init) as well as other options.
   */
  if (asprintf (&append_full, "guestfs_rescue=1%s%s",
                append ? " " : "",
                append ? append : "") == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }
  if (guestfs_set_append (g, append_full) == -1)
    exit (EXIT_FAILURE);
  free (append_full);

  /* Add an event handler to print "log messages".  These will be the
   * output of the appliance console during launch and shutdown.
   * After launch, we will read the console messages directly from the
   * socket and they won't be passed through the event callback.
   */
  if (guestfs_set_event_callback (g, log_message_callback,
                                  GUESTFS_EVENT_APPLIANCE, 0, NULL) == -1)
    exit (EXIT_FAILURE);

  /* Do the guest drives and mountpoints. */
  add_drives (drvs);
  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);
  if (inspector)
    inspect_mount ();
  mount_mps (mps);

  free_drives (drvs);
  free_mps (mps);

  /* Also bind-mount /dev etc under /sysroot, if -i was given. */
  if (inspector) {
    CLEANUP_FREE_STRING_LIST char **roots = NULL;
    int windows;

    roots = guestfs_inspect_get_roots (g);
    windows = roots && roots[0] && is_windows (g, roots[0]);
    if (!windows) {
      const char *cmd[5] = { "mount", "--rbind", NULL, NULL, NULL };
      char *r;

      cmd[2] = "/dev"; cmd[3] = "/sysroot/dev";
      r = guestfs_debug (g, "sh", (char **) cmd);
      free (r);

      cmd[2] = "/proc"; cmd[3] = "/sysroot/proc";
      r = guestfs_debug (g, "sh", (char **) cmd);
      free (r);

      cmd[2] = "/sys"; cmd[3] = "/sysroot/sys";
      r = guestfs_debug (g, "sh", (char **) cmd);
      free (r);
    }
  }

  sock = guestfs_internal_get_console_socket (g);
  if (sock == -1)
    exit (EXIT_FAILURE);

  /* Try to set all sockets to non-blocking. */
  ignore_value (set_nonblocking_flag (STDIN_FILENO, 1));
  ignore_value (set_nonblocking_flag (STDOUT_FILENO, 1));
  ignore_value (set_nonblocking_flag (sock, 1));

  /* Save the initial state of the tty so we always have the original
   * state to go back to.
   */
  if (tcgetattr (STDIN_FILENO, &old_termios) == -1) {
    perror ("tcgetattr: stdin");
    exit (EXIT_FAILURE);
  }

  /* Put stdin in raw mode so that we can receive ^C and other
   * special keys.
   */
  raw_tty ();

  /* Restore the tty settings when the process exits. */
  atexit (restore_tty);

  /* Catch tty stop and cont signals so we can cleanup.
   * See https://www.gnu.org/software/libc/manual/html_node/Signaling-Yourself.html
   */
  signal (SIGTSTP, tstp_handler);
  signal (SIGCONT, cont_handler);

  /* Print the escape key if set. */
  if (escape_key > 0)
    print_escape_key_help ();

  do_rescue (sock);

  restore_tty ();

  /* Shut down the appliance. */
  guestfs_push_error_handler (g, NULL, NULL);
  if (guestfs_shutdown (g) == -1) {
    const char *err;

    /* Ignore "appliance closed the connection unexpectedly" since
     * this can happen if the user reboots the appliance.
     */
    if (guestfs_last_errno (g) == EPIPE)
      goto next;

    /* Otherwise it's a real error. */
    err = guestfs_last_error (g);
    fprintf (stderr, "libguestfs: error: %s\n", err);
    exit (EXIT_FAILURE);
  }
 next:
  guestfs_pop_error_handler (g);
  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void
log_message_callback (guestfs_h *g, void *opaque, uint64_t event,
                      int event_handle, int flags,
                      const char *buf, size_t buf_len,
                      const uint64_t *array, size_t array_len)
{
  if (buf_len > 0) {
    ignore_value (full_write (STDOUT_FILENO, buf, buf_len));
  }
}

/* This is the main loop for virt-rescue.  We read and write
 * directly to the console socket.
 */
#define BUFSIZE 4096
static char rbuf[BUFSIZE];      /* appliance -> local tty */
static char wbuf[BUFSIZE];      /* local tty -> appliance */

static void
do_rescue (int sock)
{
  size_t rlen = 0;
  size_t wlen = 0;
  struct escape_state escape_state;

  init_escape_state (&escape_state);

  while (sock >= 0 || rlen > 0) {
    struct pollfd fds[3];
    nfds_t nfds = 2;
    int r;
    ssize_t n;

    fds[0].fd = STDIN_FILENO;
    fds[0].events = 0;
    if (BUFSIZE-wlen > 0)
      fds[0].events = POLLIN;
    fds[0].revents = 0;

    fds[1].fd = STDOUT_FILENO;
    fds[1].events = 0;
    if (rlen > 0)
      fds[1].events |= POLLOUT;
    fds[1].revents = 0;

    if (sock >= 0) {
      fds[2].fd = sock;
      fds[2].events = 0;
      if (BUFSIZE-rlen > 0)
        fds[2].events |= POLLIN;
      if (wlen > 0)
        fds[2].events |= POLLOUT;
      fds[2].revents = 0;
      nfds++;
    }

    r = poll (fds, nfds, -1);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
        continue;
      perror ("poll");
      return;
    }

    /* Input from local tty. */
    if ((fds[0].revents & POLLIN) != 0) {
      assert (BUFSIZE-wlen > 0);
      n = read (STDIN_FILENO, wbuf+wlen, BUFSIZE-wlen);
      if (n == -1) {
        if (errno == EINTR || errno == EAGAIN)
          continue;
        perror ("read");
        return;
      }
      if (n == 0) {
        /* We don't expect this to happen.  Maybe the whole tty went away?
         * Anyway, we should exit as soon as possible.
         */
        return;
      }
      if (n > 0)
        wlen += n;

      /* Process escape sequences in the tty input.  If the function
       * returns true, then we exit the loop causing virt-rescue to
       * exit.
       */
      if (escape_key > 0 && process_escapes (&escape_state, wbuf, &wlen))
        return;
    }

    /* Log message from appliance. */
    if (nfds > 2 && (fds[2].revents & POLLIN) != 0) {
      assert (BUFSIZE-rlen > 0);
      n = read (sock, rbuf+rlen, BUFSIZE-rlen);
      if (n == -1) {
        if (errno == EINTR || errno == EAGAIN)
          continue;
        if (errno == ECONNRESET)
          goto appliance_closed;
        perror ("read");
        return;
      }
      if (n == 0) {
      appliance_closed:
        sock = -1;
        /* Don't actually close the socket, because it's owned by
         * the guestfs handle.
         */
        continue;
      }
      if (n > 0)
        rlen += n;
    }

    /* Write log messages to local tty. */
    if ((fds[1].revents & POLLOUT) != 0) {
      assert (rlen > 0);
      n = write (STDOUT_FILENO, rbuf, rlen);
      if (n == -1) {
        perror ("write");
        continue;
      }
      rlen -= n;
      memmove (rbuf, rbuf+n, rlen);
    }

    /* Write commands to the appliance. */
    if (nfds > 2 && (fds[2].revents & POLLOUT) != 0) {
      assert (wlen > 0);
      n = write (sock, wbuf, wlen);
      if (n == -1) {
        perror ("write");
        continue;
      }
      wlen -= n;
      memmove (wbuf, wbuf+n, wlen);
    }
  }
}

/* Put the tty in raw mode. */
static void
raw_tty (void)
{
  struct termios termios;

  if (tcgetattr (STDIN_FILENO, &termios) == -1) {
    perror ("tcgetattr: stdin");
    _exit (EXIT_FAILURE);
  }
  cfmakeraw (&termios);
  if (tcsetattr (STDIN_FILENO, TCSANOW, &termios) == -1) {
    perror ("tcsetattr: stdin");
    _exit (EXIT_FAILURE);
  }
}

/* Restore the tty to (presumably) cooked mode as it was when
 * the program was started.
 */
static void
restore_tty (void)
{
  tcsetattr (STDIN_FILENO, TCSANOW, &old_termios);
}

/* When we get SIGTSTP, switch back to cooked mode. */
static void
tstp_handler (int sig)
{
  restore_tty ();
  signal (SIGTSTP, SIG_DFL);
  raise (SIGTSTP);
}

/* When we get SIGCONF, switch to raw mode. */
static void
cont_handler (int sig)
{
  raw_tty ();
}

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
  struct drv *drv;

  /* Add the scratch disk to the drives list. */
  drv = calloc (1, sizeof (struct drv));
  if (!drv)
    error (EXIT_FAILURE, errno, "calloc");
  drv->type = drv_scratch;
  drv->scratch.size = INT64_C (10737418240);
  drv->next = *drvs;
  *drvs = drv;
}
