/* guestfish - guest filesystem shell
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
 * guestfish, the guest filesystem shell.  This file contains the
 * main loop and utilities.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include <signal.h>
#include <errno.h>
#include <error.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <locale.h>
#include <langinfo.h>
#include <libintl.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#include <readline/history.h>
#endif

#include <guestfs.h>

#include "fish.h"
#include "options.h"
#include "display-options.h"
#include "progress.h"

#include "c-ctype.h"
#include "ignore-value.h"
#include "getprogname.h"

/* Return from parse_command_line.  See description below. */
struct parsed_command {
  int status;
  char *pipe;
  char *cmd;
  char *argv[64];
};

static void user_cancel (int);
static void prepare_drives (struct drv *drv);
static int launch (void);
static void interactive (void);
static void shell_script (void);
static void script (int prompt);
static void cmdline (char *argv[], size_t optind, size_t argc);
static struct parsed_command parse_command_line (char *buf, int *exit_on_error_rtn);
static ssize_t parse_quoted_string (char *p);
static int execute_and_inline (const char *cmd, int exit_on_error);
static void error_cb (guestfs_h *g, void *data, const char *msg);
static void initialize_readline (void);
static void cleanup_readline (void);
#ifdef HAVE_LIBREADLINE
static char *decode_ps1 (const char *);
static void add_history_line (const char *);
#endif

static int override_progress_bars = -1;
static struct progress_bar *bar = NULL;
static int pipe_error = 0;

/* Currently open libguestfs handle. */
guestfs_h *g = NULL;

int read_only = 0;
int quit = 0;
int verbose = 0;
int remote_control_listen = 0;
int remote_control_csh = 0;
int remote_control = 0;
int command_num = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;
int progress_bars = 0;
int is_interactive = 0;
const char *input_file = NULL;
int input_lineno = 0;
int in_guestfish = 1;
int in_virt_rescue = 0;

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: guest filesystem shell\n"
              "%s lets you edit virtual machine filesystems\n"
              "Copyright (C) 2009-2023 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] cmd [: cmd : cmd ...]\n"
              "Options:\n"
              "  -h|--cmd-help        List available commands\n"
              "  -h|--cmd-help cmd    Display detailed help on ‘cmd’\n"
              "  -a|--add image       Add image\n"
              "  --blocksize[=512|4096]\n"
              "                       Set sector size of the disk for -a option\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  --csh                Make --listen csh-compatible\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  --echo-keys          Don’t turn off echo for passphrases\n"
              "  -f|--file file       Read commands from file\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  --help               Display brief help\n"
              "  -i|--inspector       Automatically mount filesystems\n"
              "  --key selector       Specify a LUKS key\n"
              "  --keys-from-stdin    Read passphrases from stdin\n"
              "  --listen             Listen for remote commands\n"
              "  -m|--mount dev[:mnt[:opts[:fstype]]]\n"
              "                       Mount dev on mnt (if omitted, /)\n"
              "  --network            Enable network\n"
              "  -N|--new [filename=]type\n"
              "                       Create prepared disk (test<N>.img or filename)\n"
              "  -n|--no-sync         Don’t autosync\n"
              "  --no-dest-paths      Don’t tab-complete paths from guest fs\n"
              "  --pipe-error         Pipe commands can detect write errors\n"
              "  --progress-bars      Enable progress bars even when not interactive\n"
              "  --no-progress-bars   Disable progress bars\n"
              "  --remote[=pid]       Send commands to remote %s\n"
              "  -r|--ro              Mount read-only\n"
              "  --selinux            For backwards compat only, does nothing\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -w|--rw              Mount read-write\n"
              "  -x                   Echo each command before executing it\n"
              "\n"
              "To examine a disk image, ISO, hard disk, filesystem etc:\n"
              "  %s [--ro|--rw] -i -a /path/to/disk.img\n"
              "or\n"
              "  %s [--ro|--rw] -i -d name-of-libvirt-domain\n"
              "\n"
              "‘--ro’ is recommended to avoid any writes to the disk image.\n"
              "\n"
              "If ‘-i’ option fails run again without ‘-i’ and use ‘run’ +\n"
              "‘list-filesystems’ + ‘mount’ cmds.\n"
              "\n"
              "For more information, see the manpage %s(1).\n"),
            getprogname (), getprogname (),
            getprogname (), getprogname (),
            getprogname (), getprogname (),
            getprogname ());
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

  static const char options[] = "a:c:d:Df:h::im:nN:rvVwx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "blocksize", 2, 0, 0 },
    { "cmd-help", 2, 0, 'h' },
    { "connect", 1, 0, 'c' },
    { "csh", 0, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "file", 1, 0, 'f' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "inspector", 0, 0, 'i' },
    { "key", 1, 0, 0 },
    { "keys-from-stdin", 0, 0, 0 },
    { "listen", 0, 0, 0 },
    { "live", 0, 0, 0 },
    { "long-options", 0, 0, 0 },
    { "mount", 1, 0, 'm' },
    { "network", 0, 0, 0 },
    { "new", 1, 0, 'N' },
    { "no-dest-paths", 0, 0, 0 },
    { "no-sync", 0, 0, 'n' },
    { "pipe-error", 0, 0, 0 },
    { "progress-bars", 0, 0, 0 },
    { "no-progress-bars", 0, 0, 0 },
    { "remote", 2, 0, 0 },
    { "ro", 0, 0, 'r' },
    { "rw", 0, 0, 'w' },
    { "selinux", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  struct mp *mps = NULL;
  struct mp *mp;
  char *p, *file = NULL;
  const char *format = NULL;
  bool format_consumed = true;
  int blocksize = 0;
  bool blocksize_consumed = true;
  int c;
  int option_index;
  struct sigaction sa;
  int next_prepared_drive = 1;
  struct key_store *ks = NULL;

  initialize_readline ();
  init_event_handlers ();

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGPIPE, &sa, NULL);

  /* guestfs_create is meant to be a lightweight operation, so
   * it's OK to do it early here.
   */
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
      else if (STREQ (long_options[option_index].name, "listen"))
        remote_control_listen = 1;
      else if (STREQ (long_options[option_index].name, "remote")) {
        if (optarg) {
          if (sscanf (optarg, "%d", &remote_control) != 1)
            error (EXIT_FAILURE, 0,
                   _("--listen=PID: PID was not a number: %s"), optarg);
        } else {
          p = getenv ("GUESTFISH_PID");
          if (!p || sscanf (p, "%d", &remote_control) != 1)
            error (EXIT_FAILURE, 0,
                   _("remote: $GUESTFISH_PID must be set"
                     " to the PID of the remote process"));
        }
      } else if (STREQ (long_options[option_index].name, "selinux")) {
        /* nothing */
      } else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "progress-bars")) {
        override_progress_bars = 1;
      } else if (STREQ (long_options[option_index].name, "no-progress-bars")) {
        override_progress_bars = 0;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "blocksize")) {
        OPTION_blocksize;
      } else if (STREQ (long_options[option_index].name, "csh")) {
        remote_control_csh = 1;
      } else if (STREQ (long_options[option_index].name, "live")) {
        error (EXIT_FAILURE, 0,
               _("libguestfs live support was removed in libguestfs 1.48"));
      } else if (STREQ (long_options[option_index].name, "pipe-error")) {
        pipe_error = 1;
      } else if (STREQ (long_options[option_index].name, "network")) {
        if (guestfs_set_network (g, 1) == -1)
          exit (EXIT_FAILURE);
      } else if (STREQ (long_options[option_index].name, "no-dest-paths")) {
        complete_dest_paths = 0;
      } else if (STREQ (long_options[option_index].name, "key")) {
        OPTION_key;
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

    case 'D':
      fprintf (stderr, _("%s: warning: -D option is deprecated, use --no-dest-paths instead\n"),
               getprogname ());
      complete_dest_paths = 0;
      break;

    case 'f':
      if (file)
        error (EXIT_FAILURE, 0, _("only one -f parameter can be given"));
      file = optarg;
      break;

    case 'h': {
      int r = 0;

      if (optarg)
        r = display_command (optarg);
      else if (argv[optind] && argv[optind][0] != '-')
        r = display_command (argv[optind++]);
      else
        list_commands ();

      exit (r == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
    }

    case 'i':
      OPTION_i;
      break;

    case 'm':
      OPTION_m;
      break;

    case 'n':
      OPTION_n;
      break;

    case 'N': {
      char *p;

      if (STRCASEEQ (optarg, "list") ||
          STRCASEEQ (optarg, "help") ||
          STRCASEEQ (optarg, "h") ||
          STRCASEEQ (optarg, "?")) {
        list_prepared_drives ();
        exit (EXIT_SUCCESS);
      }
      drv = calloc (1, sizeof (struct drv));
      if (!drv)
        error (EXIT_FAILURE, errno, "calloc");
      drv->type = drv_N;
      p = strchr (optarg, '=');
      if (p != NULL) {
        *p = '\0';
        p = p+1;
        drv->N.filename = strdup (optarg);
        if (drv->N.filename == NULL)
          error (EXIT_FAILURE, errno, "strdup");
      } else {
        if (asprintf (&drv->N.filename, "test%d.img",
                      next_prepared_drive) == -1)
          error (EXIT_FAILURE, errno, "asprintf");
        p = optarg;
      }
      drv->N.data = create_prepared_file (p, drv->N.filename);
      drv->N.data_free = free_prep_data;
      drv->next = drvs;
      drvs = drv;
      next_prepared_drive++;
      break;
    }

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

  /* Decide here if this will be an interactive session.  We have to
   * do this as soon as possible after processing the command line
   * args.
   */
  is_interactive = !file && isatty (0);

  /* Register a ^C handler.  We have to do this before launch could
   * possibly be called below.
   */
  if (is_interactive) {
    memset (&sa, 0, sizeof sa);
    sa.sa_handler = user_cancel;
    sa.sa_flags = SA_RESTART;
    sigaction (SIGINT, &sa, NULL);
    sigaction (SIGQUIT, &sa, NULL);

    if (guestfs_set_pgroup (g, 1) == -1)
      exit (EXIT_FAILURE);
  }

  /* Old-style -i syntax?  Since -a/-d/-N and -i was disallowed
   * previously, if we have -i without any drives but with something
   * on the command line, it must be old-style syntax.
   */
  if (inspector && drvs == NULL && optind < argc) {
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

  CHECK_OPTION_format_consumed;
  CHECK_OPTION_blocksize_consumed;

  /* If we've got drives to add, add them now. */
  add_drives (drvs);

  if (key_store_requires_network (ks) && guestfs_set_network (g, 1) == -1)
    exit (EXIT_FAILURE);

  /* If we've got mountpoints or prepared drives or -i option, we must
   * launch the guest and mount them.
   */
  if (next_prepared_drive > 1 || mps != NULL || inspector) {
    /* RHBZ#612178: If --listen flag is given, then we will fork into
     * the background in rc_listen().  However you can't do this while
     * holding a libguestfs handle open because the recovery process
     * will think the main program has died and kill qemu.  Therefore
     * don't use the recovery process for this case.  (A better
     * solution would be to call launch () etc after the fork, but
     * that greatly complicates the code here).
     */
    if (remote_control_listen) {
      if (guestfs_set_recovery_proc (g, 0) == -1)
        exit (EXIT_FAILURE);
    }

    if (launch () == -1) exit (EXIT_FAILURE);

    if (inspector)
      inspect_mount ();

    prepare_drives (drvs);
    mount_mps (mps);
  }

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);
  free_mps (mps);
  free_key_store (ks);

  /* Remote control? */
  if (remote_control_listen && remote_control)
    error (EXIT_FAILURE, 0,
           _("cannot use --listen and --remote options at the same time"));

  if (remote_control_listen) {
    if (optind < argc)
      error (EXIT_FAILURE, 0,
             _("extra parameters on the command line with --listen flag"));
    if (file)
      error (EXIT_FAILURE, 0,
             _("cannot use --listen and --file options at the same time"));
    rc_listen ();
    goto out_after_handle_close;
  }

  /* -f (file) parameter? */
  if (file) {
    close (0);
    if (open (file, O_RDONLY|O_CLOEXEC) == -1)
      error (EXIT_FAILURE, errno, "open: %s", file);
  }

  /* Get the name of the input file, for error messages, and replace
   * the default error handler.
   */
  if (!is_interactive) {
    if (file)
      input_file = file;
    else
      input_file = "*stdin*";
    guestfs_set_error_handler (g, error_cb, NULL);
  }
  input_lineno = 0;

  /* Decide if we display progress bars. */
  progress_bars =
    override_progress_bars >= 0
    ? override_progress_bars
    : (optind >= argc && is_interactive);

  if (progress_bars) {
    bar = progress_bar_init (0);
    if (!bar)
      error (EXIT_FAILURE, errno, "progress_bar_init");

    guestfs_set_event_callback (g, progress_callback,
                                GUESTFS_EVENT_PROGRESS, 0, NULL);
  }

  /* Interactive, shell script, or command(s) on the command line? */
  if (optind >= argc) {
    if (is_interactive)
      interactive ();
    else
      shell_script ();
  }
  else
    cmdline (argv, optind, argc);

  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

 out_after_handle_close:
  cleanup_readline ();

  if (progress_bars)
    progress_bar_free (bar);

  free_event_handlers ();

  exit (EXIT_SUCCESS);
}

static void
user_cancel (int sig)
{
  if (g)
    ignore_value (guestfs_user_cancel (g));
}

static void
prepare_drives (struct drv *drv)
{
  if (drv) {
    prepare_drives (drv->next);
    if (drv->type == drv_N) {
      char device[64];

      strcpy (device, "/dev/sd");
      guestfs_int_drive_name (drv->drive_index, &device[7]);
      prepare_drive (drv->N.filename, drv->N.data, device);
    }
  }
}

static int
launch (void)
{
  if (guestfs_is_config (g)) {
    if (guestfs_launch (g) == -1)
      return -1;
  }
  return 0;
}

static void
interactive (void)
{
  script (1);
}

static void
shell_script (void)
{
  script (0);
}

#define FISH "><fs> "

#ifdef HAVE_LIBREADLINE
static char *ps1 = NULL;        /* GUESTFISH_PS1 */
static char *ps_output = NULL;  /* GUESTFISH_OUTPUT */
static char *ps_init = NULL;    /* GUESTFISH_INIT */
static char *ps_restore = NULL; /* GUESTFISH_RESTORE */
#endif /* HAVE_LIBREADLINE */
static char *line_read = NULL;

static char *
rl_gets (int prompt)
{
#ifdef HAVE_LIBREADLINE
  CLEANUP_FREE char *p = NULL;

  if (prompt) {
    if (line_read) {
      free (line_read);
      line_read = NULL;
    }

    p = ps1 ? decode_ps1 (ps1) : NULL;
    line_read = readline (ps1 ? p : FISH);

    if (ps_output) {            /* GUESTFISH_OUTPUT */
      CLEANUP_FREE char *po = decode_ps1 (ps_output);
      printf ("%s", po);
    }

    if (line_read && *line_read)
      add_history_line (line_read);

    return line_read;
  }

#endif /* HAVE_LIBREADLINE */

  static char buf[8192];
  size_t len;

  if (prompt) printf (FISH);
  line_read = fgets (buf, sizeof buf, stdin);

  if (line_read) {
    len = strlen (line_read);
    if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';
  }

  return line_read;
}

static void
script (int prompt)
{
  char *buf;
  const int global_exit_on_error = !prompt;
  int exit_on_error;
  struct parsed_command pcmd;

  if (prompt) {
#ifdef HAVE_LIBREADLINE
    if (ps_init) {              /* GUESTFISH_INIT */
      CLEANUP_FREE char *pi = decode_ps1 (ps_init);
      printf ("%s", pi);
    }
#endif /* HAVE_LIBREADLINE */

    printf (_("\n"
              "Welcome to guestfish, the guest filesystem shell for\n"
              "editing virtual machine filesystems and disk images.\n"
              "\n"
              "Type: ‘help’ for help on commands\n"
              "      ‘man’ to read the manual\n"
              "      ‘quit’ to quit the shell\n"
              "\n"));

    if (inspector) {
      print_inspect_prompt ();
      printf ("\n");
    }
  }

  while (!quit) {
    exit_on_error = global_exit_on_error;

    buf = rl_gets (prompt);
    if (!buf) {
      quit = 1;
      break;
    }

    input_lineno++;

    pcmd = parse_command_line (buf, &exit_on_error);
    if (pcmd.status == -1 && exit_on_error)
      exit (EXIT_FAILURE);
    if (pcmd.status == 1) {
      if (issue_command (pcmd.cmd, pcmd.argv, pcmd.pipe, exit_on_error) == -1) {
        if (exit_on_error) exit (EXIT_FAILURE);
      }
    }
  }

#ifdef HAVE_LIBREADLINE
  if (prompt) {
    printf ("\n");
    if (ps_restore) {           /* GUESTFISH_RESTORE */
      CLEANUP_FREE char *pr = decode_ps1 (ps_restore);
      printf ("%s", pr);
    }
  }
#endif /* HAVE_LIBREADLINE */
}

/**
 * Parse a command string, splitting at whitespace, handling C<'!'>,
 * C<'#'> etc.  This destructively updates C<buf>.
 *
 * C<exit_on_error_rtn> is used to pass in the global C<exit_on_error>
 * setting and to return the local setting (eg. if the command begins
 * with C<'-'>).
 *
 * Returns in C<parsed_command.status>:
 *
 * =over 4
 *
 * =item C<1>
 *
 * got a guestfish command (returned in C<cmd_rtn>/C<argv_rtn>/C<pipe_rtn>)
 *
 * =item C<0>
 *
 * no guestfish command, but otherwise OK
 *
 * =item C<-1>
 *
 * an error
 *
 * =back
 */
static struct parsed_command
parse_command_line (char *buf, int *exit_on_error_rtn)
{
  struct parsed_command pcmd;
  char *p, *pend;
  ssize_t len;
  int tilde_candidate;
  int r;
  const size_t argv_len = sizeof pcmd.argv / sizeof pcmd.argv[0];

  /* Note that pcmd.pipe must be set to NULL for correct usage.  Other
   * fields do not need to be, but this silences a gcc warning.
   */
  memset (&pcmd, 0, sizeof pcmd);

 again:
  /* Skip any initial whitespace before the command. */
  while (*buf && c_isspace (*buf))
    buf++;

  if (!*buf) {
    pcmd.status = 0;
    return pcmd;
  }

  /* If the next character is '#' then this is a comment. */
  if (*buf == '#') {
    pcmd.status = 0;
    return pcmd;
  }

  /* If the next character is '!' then pass the whole lot to system(3). */
  if (*buf == '!') {
    r = system (buf+1);
    if (r == -1 ||
        (WIFSIGNALED (r) &&
         (WTERMSIG (r) == SIGINT || WTERMSIG (r) == SIGQUIT)) ||
        WEXITSTATUS (r) != 0)
      pcmd.status = -1;
    else
      pcmd.status = 0;
    return pcmd;
  }

  /* If the next two characters are "<!" then pass the command to
   * popen(3), read the result and execute it as guestfish commands.
   */
  if (buf[0] == '<' && buf[1] == '!') {
    const int r = execute_and_inline (&buf[2], *exit_on_error_rtn);
    if (r == -1)
      pcmd.status = -1;
    else
      pcmd.status = 0;
    return pcmd;
  }

  /* If the next character is '-' allow the command to fail without
   * exiting on error (just for this one command though).
   */
  if (*buf == '-') {
    *exit_on_error_rtn = 0;
    buf++;
    goto again;
  }

  /* Get the command (cannot be quoted). */
  len = strcspn (buf, " \t");

  if (len == 0) {
    pcmd.status = 0;
    return pcmd;
  }

  pcmd.cmd = buf;
  unsigned int i = 0;
  if (buf[len] == '\0') {
    pcmd.argv[0] = NULL;
    pcmd.status = 1;
    return pcmd;
  }

  buf[len] = '\0';
  p = &buf[len+1];
  p += strspn (p, " \t");

  /* Get the parameters. */
  while (*p && i < argv_len) {
    tilde_candidate = 0;

    /* Parameters which start with quotes or pipes are treated
     * specially.  Bare parameters are delimited by whitespace.
     */
    if (*p == '"') {
      p++;
      len = parse_quoted_string (p);
      if (len == -1) {
        pcmd.status = -1;
        return pcmd;
      }
      if (p[len+1] && (p[len+1] != ' ' && p[len+1] != '\t')) {
        fprintf (stderr,
                 _("%s: command arguments not separated by whitespace\n"),
                 getprogname ());
        pcmd.status = -1;
        return pcmd;
      }
      pend = p[len+1] ? &p[len+2] : &p[len+1];
    } else if (*p == '\'') {
      p++;
      len = strcspn (p, "'");
      if (p[len] == '\0') {
        fprintf (stderr, _("%s: unterminated single quote\n"), getprogname ());
        pcmd.status = -1;
        return pcmd;
      }
      if (p[len+1] && (p[len+1] != ' ' && p[len+1] != '\t')) {
        fprintf (stderr,
                 _("%s: command arguments not separated by whitespace\n"),
                 getprogname ());
        pcmd.status = -1;
        return pcmd;
      }
      p[len] = '\0';
      pend = p[len+1] ? &p[len+2] : &p[len+1];
    } else if (*p == '|') {
      *p = '\0';
      pcmd.pipe = p+1;
      continue;
    } else if (*p != ' ' && *p != '\t') {
      /* If the first character is a ~ then note that this parameter
       * is a candidate for ~username expansion.  NB this does not
       * apply to quoted parameters.
       */
      tilde_candidate = *p == '~';
      len = strcspn (p, " \t");
      if (p[len]) {
        p[len] = '\0';
        pend = &p[len+1];
      } else
        pend = &p[len];
    } else {
      fprintf (stderr, _("%s: internal error parsing string at ‘%s’\n"),
               getprogname (), p);
      abort ();
    }

    if (!tilde_candidate)
      pcmd.argv[i] = p;
    else
      pcmd.argv[i] = try_tilde_expansion (p);
    i++;
    p = pend;

    if (*p)
      p += strspn (p, " \t");
  }

  if (i == argv_len) {
    fprintf (stderr, _("%s: too many arguments\n"), getprogname ());
    pcmd.status = -1;
    return pcmd;
  }

  pcmd.argv[i] = NULL;

  pcmd.status = 1;
  return pcmd;
}

static int
hexdigit (char d)
{
  switch (d) {
  case '0'...'9': return d - '0';
  case 'a'...'f': return d - 'a' + 10;
  case 'A'...'F': return d - 'A' + 10;
  default: return -1;
  }
}

/**
 * Parse double-quoted strings, replacing backslash escape sequences
 * with the true character.  Since the string is returned in place,
 * the escapes must make the string shorter.
 */
static ssize_t
parse_quoted_string (char *p)
{
  char *start = p;

  for (; *p && *p != '"'; p++) {
    if (*p == '\\') {
      int m = 1, c;

      switch (p[1]) {
      case '\\': break;
      case 'a': *p = '\a'; break;
      case 'b': *p = '\b'; break;
      case 'f': *p = '\f'; break;
      case 'n': *p = '\n'; break;
      case 'r': *p = '\r'; break;
      case 't': *p = '\t'; break;
      case 'v': *p = '\v'; break;
      case '"': *p = '"'; break;
      case '\'': *p = '\''; break;
      case '?': *p = '?'; break;

      case '0'...'7':           /* octal escape - always 3 digits */
        m = 3;
        if (p[2] >= '0' && p[2] <= '7' &&
            p[3] >= '0' && p[3] <= '7') {
          c = (p[1] - '0') * 0100 + (p[2] - '0') * 010 + (p[3] - '0');
          if (c < 1 || c > 255)
            goto error;
          *p = c;
        }
        else
          goto error;
        break;

      case 'x':                 /* hex escape - always 2 digits */
        m = 3;
        if (c_isxdigit (p[2]) && c_isxdigit (p[3])) {
          c = hexdigit (p[2]) * 0x10 + hexdigit (p[3]);
          if (c < 1 || c > 255)
            goto error;
          *p = c;
        }
        else
          goto error;
        break;

      default:
      error:
        fprintf (stderr, _("%s: invalid escape sequence in string (starting at offset %d)\n"),
                 getprogname (), (int) (p - start));
        return -1;
      }
      memmove (p+1, p+1+m, strlen (p+1+m) + 1);
    }
  }

  if (!*p) {
    fprintf (stderr, _("%s: unterminated double quote\n"), getprogname ());
    return -1;
  }

  *p = '\0';
  return p - start;
}

/**
 * Used to handle C<E<lt>!> (execute command and inline result).
 */
static int
execute_and_inline (const char *cmd, int global_exit_on_error)
{
  FILE *pp;
  CLEANUP_FREE char *line = NULL;
  size_t allocsize = 0;
  ssize_t n;
  int exit_on_error;
  struct parsed_command pcmd;

  pp = popen (cmd, "r");
  if (!pp) {
    perror ("popen");
    return -1;
  }

  while ((n = getline (&line, &allocsize, pp)) != -1) {
    exit_on_error = global_exit_on_error;

    /* Chomp final line ending which parse_command_line would not expect. */
    if (n > 0 && line[n-1] == '\n')
      line[n-1] = '\0';

    pcmd = parse_command_line (line, &exit_on_error);
    if (pcmd.status == -1 && exit_on_error)
      exit (EXIT_FAILURE);
    if (pcmd.status == 1) {
      if (issue_command (pcmd.cmd, pcmd.argv, pcmd.pipe, exit_on_error) == -1) {
        if (exit_on_error) exit (EXIT_FAILURE);
      }
    }
  }

  if (pclose (pp) != 0) {
    perror ("pclose");
    return -1;
  }

  return 0;
}

static void
cmdline (char *argv[], size_t optind, size_t argc)
{
  const char *cmd;
  char **params;
  int exit_on_error;

  exit_on_error = 1;

  if (optind >= argc) return;

  cmd = argv[optind++];
  if (STREQ (cmd, ":"))
    error (EXIT_FAILURE, 0, _("empty command on command line"));

  /* Allow -cmd on the command line to mean (temporarily) override
   * the normal exit on error (RHBZ#578407).
   */
  if (cmd[0] == '-') {
    exit_on_error = 0;
    cmd++;
  }

  params = &argv[optind];

  /* Search for end of command list or ":" ... */
  while (optind < argc && STRNEQ (argv[optind], ":"))
    optind++;

  if (optind == argc) {
    if (issue_command (cmd, params, NULL, exit_on_error) == -1 && exit_on_error)
      exit (EXIT_FAILURE);
  } else {
    argv[optind] = NULL;
    if (issue_command (cmd, params, NULL, exit_on_error) == -1 && exit_on_error)
      exit (EXIT_FAILURE);
    cmdline (argv, optind+1, argc);
  }
}

/**
 * Run a command.
 *
 * C<rc_exit_on_error_flag> is the C<exit_on_error> flag that we pass
 * to the remote server (when issuing I<--remote> commands).  It does
 * not cause C<issue_command> itself to exit on error.
 */
int
issue_command (const char *cmd, char *argv[], const char *pipecmd,
               int rc_exit_on_error_flag)
{
  size_t argc;
  int stdout_saved_fd = -1;
  int pid = 0;
  int r;

  if (progress_bars)
    progress_bar_reset (bar);

  /* This counts the commands issued, starting at 1. */
  command_num++;

  /* For | ... commands.  Annoyingly we can't use popen(3) here. */
  if (pipecmd) {
    int fd[2];

    if (fflush (stdout) == EOF) {
      perror ("failed to flush standard output");
      return -1;
    }
    if (pipe (fd) < 0) {
      perror ("pipe failed");
      return -1;
    }
    pid = fork ();
    if (pid == -1) {
      perror ("fork");
      return -1;
    }

    if (pid == 0) {		/* Child process. */
      close (fd[1]);
      if (dup2 (fd[0], 0) < 0) {
        perror ("dup2 of stdin failed");
        _exit (1);
      }

      r = system (pipecmd);
      if (r == -1) {
        perror (pipecmd);
        _exit (1);
      }
      _exit (WEXITSTATUS (r));
    }

    if ((stdout_saved_fd = dup (1)) < 0) {
      perror ("failed to dup stdout");
      return -1;
    }
    close (fd[0]);
    if (dup2 (fd[1], 1) < 0) {
      perror ("failed to dup stdout");
      close (stdout_saved_fd);
      return -1;
    }
    close (fd[1]);
  }

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;

  /* If --remote was set, then send this command to a remote process. */
  if (remote_control)
    r = rc_remote (remote_control, cmd, argc, argv, rc_exit_on_error_flag);

  /* Otherwise execute it locally. */
  else if (STRCASEEQ (cmd, "help"))
    r = display_help (cmd, argc, argv);
  else if (STRCASEEQ (cmd, "quit") ||
           STRCASEEQ (cmd, "exit") ||
           STRCASEEQ (cmd, "q")) {
    quit = 1;
    r = 0;
  }
  else
    r = run_action (cmd, argc, argv);

  /* Always flush stdout after every command, so that messages, results
   * etc appear immediately.
   */
  if (fflush (stdout) == EOF) {
    perror ("failed to flush standard output");
    if (pipecmd)
      close (stdout_saved_fd);
    return -1;
  }
  if (ferror (stdout)) {
    if (!pipecmd || pipe_error) {
      fprintf (stderr, "%s: write error%s\n", getprogname (),
               pipecmd ? " on pipe" : "");
      r = -1;
    }
    /* We've dealt with this error, so clear the flag. */
    clearerr (stdout);
  }

  if (pipecmd) {
    close (1);
    if (dup2 (stdout_saved_fd, 1) < 0) {
      perror ("failed to dup2 standard output");
      r = -1;
    }
    close (stdout_saved_fd);
    if (waitpid (pid, NULL, 0) < 0) {
      perror ("waiting for command to complete");
      r = -1;
    }
  }

  return r;
}

void
list_builtin_commands (void)
{
  /* help and quit should appear at the top */
  printf ("%-20s %s\n",
          "help", _("display a list of commands or help on a command"));
  printf ("%-20s %s\n",
          "quit", _("quit guestfish"));

  /* actions are printed after this (see list_commands) */
}

int
display_builtin_command (const char *cmd)
{
  /* help for actions is auto-generated, see display_command */

  if (STRCASEEQ (cmd, "help")) {
    printf (_("help - display a list of commands or help on a command\n"
              "     help --list\n"
              "     help cmd\n"
              "     help\n"));
    return 0;
  }
  else if (STRCASEEQ (cmd, "quit") ||
           STRCASEEQ (cmd, "exit") ||
           STRCASEEQ (cmd, "q")) {
    printf (_("quit - quit guestfish\n"
              "     quit\n"));
    return 0;
  }
  else {
    fprintf (stderr, _("%s: command not known: "), cmd);
    if (is_interactive) {
      fprintf (stderr, _("use 'help --list' to list all commands\n"));
    } else {
      fprintf (stderr, _("use -h to list all commands\n"));
    }
    return -1;
  }
}

/**
 * Print an extended help message when the user types in an unknown
 * command for the first command issued.  A common case is the user
 * doing:
 *
 *   guestfish disk.img
 *
 * expecting guestfish to open F<disk.img> (in fact, this tried to run
 * a non-existent command C<disk.img>).
 */
void
extended_help_message (void)
{
  fprintf (stderr,
           _("Did you mean to open a disk image?  guestfish -a disk.img\n"
             "For a list of commands:             guestfish -h\n"
             "For complete documentation:         man guestfish\n"));
}

/**
 * Error callback.  This replaces the standard libguestfs error handler.
 */
static void
error_cb (guestfs_h *g, void *data, const char *msg)
{
  fprintf (stderr, _("%s:%d: libguestfs: error: %s\n"),
	   input_file, input_lineno, msg);
}

void
print_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf ("%s\n", argv[argc]);
}

void
print_table (char *const *argv)
{
  size_t i;

  for (i = 0; argv[i] != NULL; i += 2)
    printf ("%s: %s\n", argv[i], argv[i+1]);
}

/**
 * Free strings from a non-NULL terminated C<char**>.
 */
static void
free_n_strings (char **str, size_t len)
{
  size_t i;

  for (i = 0; i < len; i++) {
    free (str[i]);
  }
  free (str);
}

char **
parse_string_list (const char *str)
{
  char **argv = NULL;
  size_t argv_len = 0;

  /* Current position pointer */
  const char *p = str;

  /* Token might be simple:
   *  Token
   * or be quoted:
   *  'This is a single token'
   * or contain embedded single-quoted sections:
   *  This' is a sing'l'e to'ken
   *
   * The latter may seem over-complicated, but it's what a normal shell does.
   * Not doing it risks surprising somebody.
   *
   * This outer loop is over complete tokens.
   */
  while (*p) {
    char *tok = NULL;
    size_t tok_len = 0;

    /* Skip leading whitespace */
    p += strspn (p, " \t");

    char in_quote = 0;

    /* This loop is over token 'fragments'. A token can be in multiple bits if
     * it contains single quotes. We also treat both sides of an escaped quote
     * as separate fragments because we can't just copy it: we have to remove
     * the \.
     */
    while (*p && (!c_isblank (*p) || in_quote)) {
      const char *end = p;

      /* Check if the fragment starts with a quote */
      if ('\'' == *p) {
        /* Toggle in_quote */
        in_quote = !in_quote;

        /* Skip the quote */
        p++; end++;
      }

      /* If we're in a quote, look for an end quote */
      if (in_quote) {
        end += strcspn (end, "'");
      }

      /* Otherwise, look for whitespace or a quote */
      else {
        end += strcspn (end, " \t'");
      }

      /* Grow the token to accommodate the fragment */
      const size_t tok_end = tok_len;
      tok_len += end - p;
      char *tok_new = realloc (tok, tok_len + 1);
      if (NULL == tok_new) {
        perror ("realloc");
        free_n_strings (argv, argv_len);
        free (tok);
        exit (EXIT_FAILURE);
      }
      tok = tok_new;

      /* Check if we stopped on an escaped quote */
      if ('\'' == *end && end != p && *(end-1) == '\\') {
        /* Add everything before \' to the token */
        memcpy (&tok[tok_end], p, end - p - 1);

        /* Add the quote */
        tok[tok_len-1] = '\'';

        /* Already processed the quote */
        p = end + 1;
      }

      else {
        /* Add the whole fragment */
        memcpy (&tok[tok_end], p, end - p);

        p = end;
      }
    }

    /* We've reached the end of a token. We shouldn't still be in quotes. */
    if (in_quote) {
      fprintf (stderr, _("Runaway quote in string \"%s\"\n"), str);
      free_n_strings (argv, argv_len);
      free (tok);
      return NULL;
    }

    /* Add this token if there is one. There might not be if there was
     * whitespace at the end of the input string */
    if (tok) {
      /* Add the NULL terminator */
      tok[tok_len] = '\0';

      /* Add the argument to the argument list */
      argv_len++;
      char **argv_new = realloc (argv, sizeof (*argv) * argv_len);
      if (NULL == argv_new) {
        perror ("realloc");
        free_n_strings (argv, argv_len-1);
        free (tok);
        exit (EXIT_FAILURE);
      }
      argv = argv_new;

      argv[argv_len-1] = tok;
    }
  }

  /* NULL terminate the argument list */
  argv_len++;
  char **argv_new = realloc (argv, sizeof (*argv) * argv_len);
  if (NULL == argv_new) {
    perror ("realloc");
    free_n_strings (argv, argv_len-1);
    exit (EXIT_FAILURE);
  }
  argv = argv_new;

  argv[argv_len-1] = NULL;

  return argv;
}

#ifdef HAVE_LIBREADLINE
static char histfile[1024];
static int nr_history_lines = 0;
#endif

static void
initialize_readline (void)
{
#ifdef HAVE_LIBREADLINE
  const char *str;

  rl_readline_name = "guestfish";
  rl_attempted_completion_function = do_completion;

  /* Note that .inputrc (or /etc/inputrc) is not read until the first
   * call the readline(), which happens later.  Therefore, these
   * provide default values which can be overridden by the user if
   * they wish.
   */
  (void) rl_variable_bind ("completion-ignore-case", "on");

  /* Set up the history file. */
  str = getenv ("HOME");
  if (str) {
    snprintf (histfile, sizeof histfile, "%s/.guestfish", str);
    using_history ();
    (void) read_history (histfile);
  }

  /* Set up the prompt. */
  str = getenv ("GUESTFISH_PS1");
  if (str) {
    free (ps1);
    ps1 = strdup (str);
    if (!ps1)
      error (EXIT_FAILURE, errno, "strdup");
  }

  str = getenv ("GUESTFISH_OUTPUT");
  if (str) {
    free (ps_output);
    ps_output = strdup (str);
    if (!ps_output)
      error (EXIT_FAILURE, errno, "strdup");
  }

  str = getenv ("GUESTFISH_INIT");
  if (str) {
    free (ps_init);
    ps_init = strdup (str);
    if (!ps_init)
      error (EXIT_FAILURE, errno, "strdup");
  }
#endif
}

static void
cleanup_readline (void)
{
#ifdef HAVE_LIBREADLINE
  int fd;

  if (histfile[0] != '\0') {
    fd = open (histfile, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0600);
    if (fd == -1) {
      perror (histfile);
      return;
    }
    close (fd);

#ifdef HAVE_APPEND_HISTORY
    (void) append_history (nr_history_lines, histfile);
#else
    (void) write_history (histfile);
#endif
    clear_history ();
  }
#endif
}

#ifdef HAVE_LIBREADLINE
static void
add_history_line (const char *line)
{
  add_history (line);
  nr_history_lines++;
}

static int decode_ps1_octal (const char *s, size_t *i);
static int decode_ps1_hex (const char *s, size_t *i);

/**
 * Decode C<str> into the final printable prompt string.
 */
static char *
decode_ps1 (const char *str)
{
  char *ret;
  const size_t len = strlen (str);
  size_t i, j;

  /* Result string is always smaller than the input string.  This will
   * change if we add new features like date/time substitution in
   * future.
   */
  ret = malloc (len + 1);
  if (!ret)
    error (EXIT_FAILURE, errno, "malloc");

  for (i = j = 0; i < len; ++i) {
    if (str[i] == '\\') {       /* Start of an escape sequence. */
      if (i < len-1)
        i++;
      switch (str[i]) {
      case '\\':
        ret[j++] = '\\';
        break;
      case '[':
        ret[j++] = RL_PROMPT_START_IGNORE;
        break;
      case ']':
        ret[j++] = RL_PROMPT_END_IGNORE;
        break;
      case 'a':
        ret[j++] = '\a';
        break;
      case 'e':
        ret[j++] = '\033';
        break;
      case 'n':
        ret[j++] = '\n';
        break;
      case 'r':
        ret[j++] = '\r';
        break;
      case '0'...'7':
        ret[j++] = decode_ps1_octal (str, &i);
        i--;
        break;
      case 'x':
        i++;
        ret[j++] = decode_ps1_hex (str, &i);
        i--;
        break;
      default:
        ret[j++] = '?';
      }
    }
    else
      ret[j++] = str[i];
  }

  ret[j] = '\0';
  return ret;                   /* caller frees */
}

static int
decode_ps1_octal (const char *s, size_t *i)
{
  size_t lim = 3;
  int ret = 0;

  while (lim > 0 && s[*i] >= '0' && s[*i] <= '7') {
    ret *= 8;
    ret += s[*i] - '0';
    (*i)++;
    lim--;
  }

  return ret;
}

static int
decode_ps1_hex (const char *s, size_t *i)
{
  size_t lim = 2;
  int ret = 0;

  while (lim > 0 && c_isxdigit (s[*i])) {
    ret *= 16;
    if (s[*i] >= '0' && s[*i] <= '9')
      ret += s[*i] - '0';
    else if (s[*i] >= 'a' && s[*i] <= 'f')
      ret += s[*i] - 'a' + 10;
    else if (s[*i] >= 'A' && s[*i] <= 'F')
      ret += s[*i] - 'A' + 10;
    (*i)++;
    lim--;
  }

  if (lim == 2)                 /* \x not followed by any hex digits */
    return '?';

  return ret;
}
#endif

int
xwrite (int fd, const void *v_buf, size_t len)
{
  int r;
  const char *buf = v_buf;

  while (len > 0) {
    r = write (fd, buf, len);
    if (r == -1) {
      perror ("write");
      return -1;
    }
    buf += r;
    len -= r;
  }

  return 0;
}

static char *win_prefix_drive_letter (char drive_letter, const char *path);

/**
 * Resolve the special C<win:...> form for Windows-specific paths.
 * The generated code calls this for all device or path arguments.
 *
 * The function returns a newly allocated string, and the caller must
 * free this string; else display an error and return C<NULL>.
 */
char *
win_prefix (const char *path)
{
  char *ret;
  size_t i;

  /* If there is not a "win:..." prefix on the path, return strdup'd string. */
  if (STRCASENEQLEN (path, "win:", 4)) {
    ret = strdup (path);
    if (ret == NULL)
      perror ("strdup");
    return ret;
  }

  path += 4;

  /* If there is a drive letter, rewrite the path. */
  if (c_isalpha (path[0]) && path[1] == ':') {
    char drive_letter = c_tolower (path[0]);
    /* This returns the newly allocated string. */
    ret = win_prefix_drive_letter (drive_letter, path + 2);
    if (ret == NULL)
      return NULL;
  }
  else if (!*path) {
    ret = strdup ("/");
    if (ret == NULL) {
      perror ("strdup");
      return NULL;
    }
  }
  else {
    ret = strdup (path);
    if (ret == NULL) {
      perror ("strdup");
      return NULL;
    }
  }

  /* Blindly convert any backslashes into forward slashes.  Is this good? */
  for (i = 0; i < strlen (ret); ++i)
    if (ret[i] == '\\')
      ret[i] = '/';

  char *t = guestfs_case_sensitive_path (g, ret);
  free (ret);
  ret = t;

  return ret;
}

static char *
win_prefix_drive_letter (char drive_letter, const char *path)
{
  CLEANUP_FREE_STRING_LIST char **roots = NULL;
  CLEANUP_FREE_STRING_LIST char **drives = NULL;
  CLEANUP_FREE_STRING_LIST char **mountpoints = NULL;
  char *device, *mountpoint, *ret = NULL;
  size_t i;

  /* Resolve the drive letter using the drive mappings table. */
  roots = guestfs_inspect_get_roots (g);
  if (roots == NULL)
    return NULL;
  if (roots[0] == NULL) {
    fprintf (stderr, _("%s: to use Windows drive letters, you must inspect the guest (\"-i\" option or run \"inspect-os\" command)\n"),
             getprogname ());
    return NULL;
  }
  drives = guestfs_inspect_get_drive_mappings (g, roots[0]);
  if (drives == NULL || drives[0] == NULL) {
    fprintf (stderr, _("%s: to use Windows drive letters, this must be a Windows guest\n"),
             getprogname ());
    return NULL;
  }

  device = NULL;
  for (i = 0; drives[i] != NULL; i += 2) {
    if (c_tolower (drives[i][0]) == drive_letter && drives[i][1] == '\0') {
      device = drives[i+1];
      break;
    }
  }

  if (device == NULL) {
    fprintf (stderr, _("%s: drive '%c:' not found.  To list available drives do:\n  inspect-get-drive-mappings %s\n"),
             getprogname (), drive_letter, roots[0]);
    return NULL;
  }

  /* This drive letter must be mounted somewhere (we won't do it). */
  mountpoints = guestfs_mountpoints (g);
  if (mountpoints == NULL)
    return NULL;

  mountpoint = NULL;
  for (i = 0; mountpoints[i] != NULL; i += 2) {
    if (STREQ (mountpoints[i], device)) {
      mountpoint = mountpoints[i+1];
      break;
    }
  }

  if (mountpoint == NULL) {
    fprintf (stderr, _("%s: to access '%c:', mount %s first.  One way to do this is:\n  umount-all\n  mount %s /\n"),
             getprogname (), drive_letter, device, device);
    return NULL;
  }

  /* Rewrite the path, eg. if C: => /c then C:/foo => /c/foo */
  if (asprintf (&ret, "%s%s%s",
                mountpoint, STRNEQ (mountpoint, "/") ? "/" : "", path) == -1) {
    perror ("asprintf");
    return NULL;
  }

  return ret;
}

static char *file_in_heredoc (const char *endmarker);
static char *file_in_tmpfile = NULL;

/**
 * Resolve the special C<FileIn> paths (C<-> or C<-<<END> or filename).
 *
 * The caller (F<fish/cmds.c>) will call C<free_file_in> after the
 * command has run which should clean up resources.
 */
char *
file_in (const char *arg)
{
  char *ret;

  if (STREQ (arg, "-")) {
    ret = strdup ("/dev/stdin");
    if (!ret) {
      perror ("strdup");
      return NULL;
    }
  }
  else if (STRPREFIX (arg, "-<<")) {
    const char *endmarker = &arg[3];
    if (*endmarker == '\0') {
      fprintf (stderr, "%s: missing end marker in -<< expression\n",
               getprogname ());
      return NULL;
    }
    ret = file_in_heredoc (endmarker);
    if (ret == NULL)
      return NULL;
  }
  else {
    ret = strdup (arg);
    if (!ret) {
      perror ("strdup");
      return NULL;
    }
  }

  return ret;
}

static char *
file_in_heredoc (const char *endmarker)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g), *template = NULL;
  int fd;
  size_t markerlen;
  CLEANUP_FREE char *buffer = NULL;
  int write_error = 0;

  buffer = malloc (BUFSIZ);
  if (buffer == NULL) {
    perror ("malloc");
    return NULL;
  }

  if (asprintf (&template, "%s/guestfishXXXXXX", tmpdir) == -1) {
    perror ("asprintf");
    return NULL;
  }

  file_in_tmpfile = strdup (template);
  if (file_in_tmpfile == NULL) {
    perror ("strdup");
    return NULL;
  }

  fd = mkstemp (file_in_tmpfile);
  if (fd == -1) {
    perror ("mkstemp");
    goto error1;
  }

  markerlen = strlen (endmarker);

  while (fgets (buffer, BUFSIZ, stdin) != NULL) {
    /* Look for "END"<EOF> or "END\n" in input. */
    const size_t blen = strlen (buffer);
    if (STREQLEN (buffer, endmarker, markerlen) &&
        (blen == markerlen ||
         (blen == markerlen+1 && buffer[markerlen] == '\n')))
      goto found_end;

    if (xwrite (fd, buffer, blen) == -1) {
      if (!write_error) perror ("write");
      write_error = 1;
      /* continue reading up to the end marker */
    }
  }

  /* Reached EOF of stdin without finding the end marker, which
   * is likely to be an error.
   */
  fprintf (stderr, "%s: end of input reached without finding '%s'\n",
           getprogname (), endmarker);
  goto error2;

 found_end:
  if (write_error) {
    close (fd);
    goto error2;
  }

  if (close (fd) == -1) {
    perror ("close");
    goto error2;
  }

  return file_in_tmpfile;

 error2:
  unlink (file_in_tmpfile);

 error1:
  free (file_in_tmpfile);
  file_in_tmpfile = NULL;
  return NULL;
}

void
free_file_in (char *s)
{
  if (file_in_tmpfile) {
    if (unlink (file_in_tmpfile) == -1)
      perror (file_in_tmpfile);
    file_in_tmpfile = NULL;
  }

  /* Free the device or file name which was strdup'd in file_in().
   * Note it's not immediately clear, but for -<< heredocs,
   * s == file_in_tmpfile, so this frees up that buffer.
   */
  free (s);
}

/**
 * Resolve the special C<FileOut> paths (C<-> or filename).
 *
 * The caller (F<fish/cmds.c>) will call S<C<free (str)>> after the
 * command has run.
 */
char *
file_out (const char *arg)
{
  char *ret;

  if (STREQ (arg, "-"))
    ret = strdup ("/dev/stdout");
  else
    ret = strdup (arg);

  if (!ret) {
    perror ("strdup");
    return NULL;
  }
  return ret;
}

/**
 * Callback which displays a progress bar.
 */
void
progress_callback (guestfs_h *g, void *data,
                   uint64_t event, int event_handle, int flags,
                   const char *buf, size_t buf_len,
                   const uint64_t *array, size_t array_len)
{
  if (array_len < 4)
    return;

  /*uint64_t proc_nr = array[0];*/
  /*uint64_t serial = array[1];*/
  uint64_t position = array[2];
  uint64_t total = array[3];

  progress_bar_set (bar, position, total);
}
