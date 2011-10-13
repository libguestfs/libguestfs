/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009-2011 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <locale.h>
#include <langinfo.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#include <readline/history.h>
#endif

#include <guestfs.h>

#include "fish.h"
#include "options.h"
#include "progress.h"

#include "c-ctype.h"
#include "closeout.h"
#include "progname.h"

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
static void cmdline (char *argv[], int optind, int argc);
static struct parsed_command parse_command_line (char *buf, int *exit_on_error_rtn);
static int parse_quoted_string (char *p);
static int execute_and_inline (const char *cmd, int exit_on_error);
static void error_cb (guestfs_h *g, void *data, const char *msg);
static void initialize_readline (void);
static void cleanup_readline (void);
#ifdef HAVE_LIBREADLINE
static void add_history_line (const char *);
#endif

static int override_progress_bars = -1;
static struct progress_bar *bar = NULL;

/* Currently open libguestfs handle. */
guestfs_h *g = NULL;

int read_only = 0;
int live = 0;
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

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             program_name);
  else {
    fprintf (stdout,
           _("%s: guest filesystem shell\n"
             "%s lets you edit virtual machine filesystems\n"
             "Copyright (C) 2009-2011 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] cmd [: cmd : cmd ...]\n"
             "Options:\n"
             "  -h|--cmd-help        List available commands\n"
             "  -h|--cmd-help cmd    Display detailed help on 'cmd'\n"
             "  -a|--add image       Add image\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  --csh                Make --listen csh-compatible\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  -D|--no-dest-paths   Don't tab-complete paths from guest fs\n"
             "  --echo-keys          Don't turn off echo for passphrases\n"
             "  -f|--file file       Read commands from file\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  -i|--inspector       Automatically mount filesystems\n"
             "  --keys-from-stdin    Read passphrases from stdin\n"
             "  --listen             Listen for remote commands\n"
             "  --live               Connect to a live virtual machine\n"
             "  -m|--mount dev[:mnt[:opts]] Mount dev on mnt (if omitted, /)\n"
             "  -n|--no-sync         Don't autosync\n"
             "  -N|--new type        Create prepared disk (test1.img, ...)\n"
             "  --progress-bars      Enable progress bars even when not interactive\n"
             "  --no-progress-bars   Disable progress bars\n"
             "  --remote[=pid]       Send commands to remote %s\n"
             "  -r|--ro              Mount read-only\n"
             "  --selinux            Enable SELinux support\n"
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
             "--ro recommended to avoid any writes to the disk image.  If -i option fails\n"
             "run again without -i and use 'run' + 'list-filesystems' + 'mount' cmds.\n"
             "\n"
             "For more information, see the manpage %s(1).\n"),
             program_name, program_name, program_name,
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

  atexit (close_stdout);

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  parse_config ();

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:c:d:Df:h::im:nN:rv?Vwx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "cmd-help", 2, 0, 'h' },
    { "connect", 1, 0, 'c' },
    { "csh", 0, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "file", 1, 0, 'f' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "inspector", 0, 0, 'i' },
    { "keys-from-stdin", 0, 0, 0 },
    { "listen", 0, 0, 0 },
    { "live", 0, 0, 0 },
    { "mount", 1, 0, 'm' },
    { "new", 1, 0, 'N' },
    { "no-dest-paths", 0, 0, 'D' },
    { "no-sync", 0, 0, 'n' },
    { "progress-bars", 0, 0, 0 },
    { "no-progress-bars", 0, 0, 0 },
    { "remote", 2, 0, 0 },
    { "ro", 0, 0, 'r' },
    { "rw", 0, 0, 'w' },
    { "selinux", 0, 0, 0 },
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
  int c;
  int option_index;
  struct sigaction sa;
  int next_prepared_drive = 1;

  initialize_readline ();

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGPIPE, &sa, NULL);

  /* guestfs_create is meant to be a lightweight operation, so
   * it's OK to do it early here.
   */
  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  /* CAUTION: we are careful to modify argv[0] here, only after
   * using it just above.
   *
   * getopt_long uses argv[0], so give it the sanitized name.  Save a copy
   * of the original, in case it's needed below.
   */
  //char *real_argv0 = argv[0];
  argv[0] = bad_cast (program_name);

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "listen"))
        remote_control_listen = 1;
      else if (STREQ (long_options[option_index].name, "remote")) {
        if (optarg) {
          if (sscanf (optarg, "%d", &remote_control) != 1) {
            fprintf (stderr, _("%s: --listen=PID: PID was not a number: %s\n"),
                     program_name, optarg);
            exit (EXIT_FAILURE);
          }
        } else {
          p = getenv ("GUESTFISH_PID");
          if (!p || sscanf (p, "%d", &remote_control) != 1) {
            fprintf (stderr, _("%s: remote: $GUESTFISH_PID must be set"
                               " to the PID of the remote process\n"),
                     program_name);
            exit (EXIT_FAILURE);
          }
        }
      } else if (STREQ (long_options[option_index].name, "selinux")) {
        guestfs_set_selinux (g, 1);
      } else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "progress-bars")) {
        override_progress_bars = 1;
      } else if (STREQ (long_options[option_index].name, "no-progress-bars")) {
        override_progress_bars = 0;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        if (!optarg || STREQ (optarg, ""))
          format = NULL;
        else
          format = optarg;
      } else if (STREQ (long_options[option_index].name, "csh")) {
        remote_control_csh = 1;
      } else if (STREQ (long_options[option_index].name, "live")) {
        live = 1;
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

    case 'D':
      complete_dest_paths = 0;
      break;

    case 'f':
      if (file) {
        fprintf (stderr, _("%s: only one -f parameter can be given\n"),
                 program_name);
        exit (EXIT_FAILURE);
      }
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

    case 'N':
      if (STRCASEEQ (optarg, "list") ||
          STRCASEEQ (optarg, "help") ||
          STRCASEEQ (optarg, "h") ||
          STRCASEEQ (optarg, "?")) {
        list_prepared_drives ();
        exit (EXIT_SUCCESS);
      }
      drv = malloc (sizeof (struct drv));
      if (!drv) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      drv->type = drv_N;
      drv->device = NULL;
      drv->nr_drives = -1;
      if (asprintf (&drv->N.filename, "test%d.img",
                    next_prepared_drive++) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      drv->N.data = create_prepared_file (optarg, drv->N.filename);
      drv->N.data_free = free_prep_data;
      drv->next = drvs;
      drvs = drv;
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

    guestfs_set_pgroup (g, 1);
  }

  /* Old-style -i syntax?  Since -a/-d/-N and -i was disallowed
   * previously, if we have -i without any drives but with something
   * on the command line, it must be old-style syntax.
   */
  if (inspector && drvs == NULL && optind < argc) {
    while (optind < argc) {
      if (strchr (argv[optind], '/') ||
          access (argv[optind], F_OK) == 0) { /* simulate -a option */
        drv = malloc (sizeof (struct drv));
        if (!drv) {
          perror ("malloc");
          exit (EXIT_FAILURE);
        }
        drv->type = drv_a;
        drv->a.filename = argv[optind];
        drv->a.format = NULL;
        drv->next = drvs;
        drvs = drv;
      } else {                  /* simulate -d option */
        drv = malloc (sizeof (struct drv));
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

  /* If we've got drives to add, add them now. */
  add_drives (drvs, 'a');

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
    if (remote_control_listen)
      guestfs_set_recovery_proc (g, 0);

    if (launch () == -1) exit (EXIT_FAILURE);

    if (inspector)
      inspect_mount ();

    prepare_drives (drvs);
    mount_mps (mps);
  }

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);
  free_mps (mps);

  /* Remote control? */
  if (remote_control_listen && remote_control) {
    fprintf (stderr,
             _("%s: cannot use --listen and --remote options at the same time\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  if (remote_control_listen) {
    if (optind < argc) {
      fprintf (stderr,
               _("%s: extra parameters on the command line with --listen flag\n"),
               program_name);
      exit (EXIT_FAILURE);
    }
    if (file) {
      fprintf (stderr,
               _("%s: cannot use --listen and --file options at the same time\n"),
               program_name);
      exit (EXIT_FAILURE);
    }
    rc_listen ();
  }

  /* -f (file) parameter? */
  if (file) {
    close (0);
    if (open (file, O_RDONLY) == -1) {
      perror (file);
      exit (EXIT_FAILURE);
    }
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
    if (!bar) {
      perror ("progress_bar_init");
      exit (EXIT_FAILURE);
    }

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

  cleanup_readline ();

  if (progress_bars)
    progress_bar_free (bar);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void
user_cancel (int sig)
{
  if (g)
    guestfs_user_cancel (g);
}

static void
prepare_drives (struct drv *drv)
{
  if (drv) {
    prepare_drives (drv->next);
    if (drv->type == drv_N)
      prepare_drive (drv->N.filename, drv->N.data, drv->device);
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

static char *line_read = NULL;

static char *
rl_gets (int prompt)
{
#ifdef HAVE_LIBREADLINE

  if (prompt) {
    if (line_read) {
      free (line_read);
      line_read = NULL;
    }

    line_read = readline (prompt ? FISH : "");

    if (line_read && *line_read)
      add_history_line (line_read);

    return line_read;
  }

#endif /* HAVE_LIBREADLINE */

  static char buf[8192];
  int len;

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
  int global_exit_on_error = !prompt;
  int exit_on_error;
  struct parsed_command pcmd;

  if (prompt) {
    printf (_("\n"
              "Welcome to guestfish, the libguestfs filesystem interactive shell for\n"
              "editing virtual machine filesystems.\n"
              "\n"
              "Type: 'help' for help on commands\n"
              "      'man' to read the manual\n"
              "      'quit' to quit the shell\n"
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
  if (prompt) printf ("\n");
}

/* Parse a command string, splitting at whitespace, handling '!', '#' etc.
 * This destructively updates 'buf'.
 *
 * 'exit_on_error_rtn' is used to pass in the global exit_on_error
 * setting and to return the local setting (eg. if the command begins
 * with '-').
 *
 * Returns in parsed_command.status:
 *   1 = got a guestfish command (returned in cmd_rtn/argv_rtn/pipe_rtn)
 *   0 = no guestfish command, but otherwise OK
 *  -1 = an error
 */
static struct parsed_command
parse_command_line (char *buf, int *exit_on_error_rtn)
{
  struct parsed_command pcmd;
  char *p, *pend;
  int len;
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
    int r = execute_and_inline (&buf[2], *exit_on_error_rtn);
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
                 program_name);
        pcmd.status = -1;
        return pcmd;
      }
      pend = p[len+1] ? &p[len+2] : &p[len+1];
    } else if (*p == '\'') {
      p++;
      len = strcspn (p, "'");
      if (p[len] == '\0') {
        fprintf (stderr, _("%s: unterminated single quote\n"), program_name);
        pcmd.status = -1;
        return pcmd;
      }
      if (p[len+1] && (p[len+1] != ' ' && p[len+1] != '\t')) {
        fprintf (stderr,
                 _("%s: command arguments not separated by whitespace\n"),
                 program_name);
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
      fprintf (stderr, _("%s: internal error parsing string at '%s'\n"),
               program_name, p);
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
    fprintf (stderr, _("%s: too many arguments\n"), program_name);
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

/* Parse double-quoted strings, replacing backslash escape sequences
 * with the true character.  Since the string is returned in place,
 * the escapes must make the string shorter.
 */
static int
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
                 program_name, (int) (p - start));
        return -1;
      }
      memmove (p+1, p+1+m, strlen (p+1+m) + 1);
    }
  }

  if (!*p) {
    fprintf (stderr, _("%s: unterminated double quote\n"), program_name);
    return -1;
  }

  *p = '\0';
  return p - start;
}

/* Used to handle "<!" (execute command and inline result). */
static int
execute_and_inline (const char *cmd, int global_exit_on_error)
{
  FILE *pp;
  char *line = NULL;
  size_t len = 0;
  ssize_t n;
  int exit_on_error;
  struct parsed_command pcmd;

  pp = popen (cmd, "r");
  if (!pp) {
    perror ("popen");
    return -1;
  }

  while ((n = getline (&line, &len, pp)) != -1) {
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

  free (line);

  if (pclose (pp) != 0) {
    perror ("pclose");
    return -1;
  }

  return 0;
}

static void
cmdline (char *argv[], int optind, int argc)
{
  const char *cmd;
  char **params;
  int exit_on_error;

  exit_on_error = 1;

  if (optind >= argc) return;

  cmd = argv[optind++];
  if (STREQ (cmd, ":")) {
    fprintf (stderr, _("%s: empty command on command line\n"), program_name);
    exit (EXIT_FAILURE);
  }

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

/* Note: 'rc_exit_on_error_flag' is the exit_on_error flag that we
 * pass to the remote server (when issuing --remote commands).  It
 * does not cause issue_command itself to exit on error.
 */
int
issue_command (const char *cmd, char *argv[], const char *pipecmd,
               int rc_exit_on_error_flag)
{
  int argc;
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
  else if (STRCASEEQ (cmd, "help")) {
    if (argc == 0) {
      display_help ();
      r = 0;
    } else
      r = display_command (argv[0]);
  }
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
    return -1;
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
    fprintf (stderr, _("%s: command not known, use -h to list all commands\n"),
             cmd);
    return -1;
  }
}

/* This is printed when the user types in an unknown command for the
 * first command issued.  A common case is the user doing:
 *   guestfish disk.img
 * expecting guestfish to open 'disk.img' (in fact, this tried to
 * run a command 'disk.img').
 */
void
extended_help_message (void)
{
  fprintf (stderr,
           _("Did you mean to open a disk image?  guestfish -a disk.img\n"
             "For a list of commands:             guestfish -h\n"
             "For complete documentation:         man guestfish\n"));
}

/* Error callback.  This replaces the standard libguestfs error handler. */
static void
error_cb (guestfs_h *g, void *data, const char *msg)
{
  fprintf (stderr, _("%s:%d: libguestfs: error: %s\n"),
	   input_file, input_lineno, msg);
}

void
free_strings (char **argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    free (argv[argc]);
  free (argv);
}

int
count_strings (char *const *argv)
{
  int c;

  for (c = 0; argv[c]; ++c)
    ;
  return c;
}

void
print_strings (char *const *argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf ("%s\n", argv[argc]);
}

void
print_table (char *const *argv)
{
  int i;

  for (i = 0; argv[i] != NULL; i += 2)
    printf ("%s: %s\n", argv[i], argv[i+1]);
}

int
is_true (const char *str)
{
  return
    STRCASENEQ (str, "0") &&
    STRCASENEQ (str, "f") &&
    STRCASENEQ (str, "false") &&
    STRCASENEQ (str, "n") &&
    STRCASENEQ (str, "no");
}

/* Free strings from a non-NULL terminated char** */
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
      size_t tok_end = tok_len;
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
  const char *home;

  home = getenv ("HOME");
  if (home) {
    snprintf (histfile, sizeof histfile, "%s/.guestfish", home);
    using_history ();
    (void) read_history (histfile);
  }

  rl_readline_name = "guestfish";
  rl_attempted_completion_function = do_completion;

  /* Note that .inputrc (or /etc/inputrc) is not read until the first
   * call the readline(), which happens later.  Therefore, these
   * provide default values which can be overridden by the user if
   * they wish.
   */
  (void) rl_variable_bind ("completion-ignore-case", "on");
#endif
}

static void
cleanup_readline (void)
{
#ifdef HAVE_LIBREADLINE
  int fd;

  if (histfile[0] != '\0') {
    fd = open (histfile, O_WRONLY|O_CREAT, 0644);
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

/* Resolve the special "win:..." form for Windows-specific paths.  The
 * generated code calls this for all device or path arguments.
 *
 * The function returns a newly allocated string, and the caller must
 * free this string; else display an error and return NULL.
 */
static char *win_prefix_drive_letter (char drive_letter, const char *path);

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
  char **roots = NULL;
  char **drives = NULL;
  char **mountpoints = NULL;
  char *device, *mountpoint, *ret = NULL;
  size_t i;

  /* Resolve the drive letter using the drive mappings table. */
  roots = guestfs_inspect_get_roots (g);
  if (roots == NULL)
    goto out;
  if (roots[0] == NULL) {
    fprintf (stderr, _("%s: to use Windows drive letters, you must inspect the guest (\"-i\" option or run \"inspect-os\" command)\n"),
             program_name);
    goto out;
  }
  drives = guestfs_inspect_get_drive_mappings (g, roots[0]);
  if (drives == NULL || drives[0] == NULL) {
    fprintf (stderr, _("%s: to use Windows drive letters, this must be a Windows guest\n"),
             program_name);
    goto out;
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
             program_name, drive_letter, roots[0]);
    goto out;
  }

  /* This drive letter must be mounted somewhere (we won't do it). */
  mountpoints = guestfs_mountpoints (g);
  if (mountpoints == NULL)
    goto out;

  mountpoint = NULL;
  for (i = 0; mountpoints[i] != NULL; i += 2) {
    if (STREQ (mountpoints[i], device)) {
      mountpoint = mountpoints[i+1];
      break;
    }
  }

  if (mountpoint == NULL) {
    fprintf (stderr, _("%s: to access '%c:', mount %s first.  One way to do this is:\n  umount-all\n  mount %s /\n"),
             program_name, drive_letter, device, device);
    goto out;
  }

  /* Rewrite the path, eg. if C: => /c then C:/foo => /c/foo */
  if (asprintf (&ret, "%s%s%s",
                mountpoint, STRNEQ (mountpoint, "/") ? "/" : "", path) == -1) {
    perror ("asprintf");
    goto out;
  }

 out:
  if (roots)
    free_strings (roots);
  if (drives)
    free_strings (drives);
  if (mountpoints)
    free_strings (mountpoints);

  return ret;
}

/* Resolve the special FileIn paths ("-" or "-<<END" or filename).
 * The caller (cmds.c) will call free_file_in after the command has
 * run which should clean up resources.
 */
static char *file_in_heredoc (const char *endmarker);
static char *file_in_tmpfile = NULL;

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
               program_name);
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
  TMP_TEMPLATE_ON_STACK (template);
  file_in_tmpfile = strdup (template);
  if (file_in_tmpfile == NULL) {
    perror ("strdup");
    return NULL;
  }

  int fd = mkstemp (file_in_tmpfile);
  if (fd == -1) {
    perror ("mkstemp");
    goto error1;
  }

  size_t markerlen = strlen (endmarker);

  char buffer[BUFSIZ];
  int write_error = 0;
  while (fgets (buffer, sizeof buffer, stdin) != NULL) {
    /* Look for "END"<EOF> or "END\n" in input. */
    size_t blen = strlen (buffer);
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
           program_name, endmarker);
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

/* Resolve the special FileOut paths ("-" or filename).
 * The caller (cmds.c) will call free (str) after the command has run.
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

/* Callback which displays a progress bar. */
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
