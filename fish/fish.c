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

static void set_up_terminal (void);
static void prepare_drives (struct drv *drv);
static int launch (void);
static void interactive (void);
static void shell_script (void);
static void script (int prompt);
static void cmdline (char *argv[], int optind, int argc);
static struct parsed_command parse_command_line (char *buf, int *exit_on_error_rtn);
static int execute_and_inline (const char *cmd, int exit_on_error);
static void initialize_readline (void);
static void cleanup_readline (void);
#ifdef HAVE_LIBREADLINE
static void add_history_line (const char *);
#endif

static int override_progress_bars = -1;

/* Currently open libguestfs handle. */
guestfs_h *g;

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
int utf8_mode = 0;
int have_terminfo = 0;
int progress_bars = 0;

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
             "  %s [--ro] -i -a disk-image\n"
             "  %s [--ro] -i -d libvirt-domain\n"
             "or for interactive use:\n"
             "  %s\n"
             "or from a shell script:\n"
             "  %s <<EOF\n"
             "  cmd\n"
             "  ...\n"
             "  EOF\n"
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
             "  -m|--mount dev[:mnt] Mount dev on mnt (if omitted, /)\n"
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
             "For more information, see the manpage %s(1).\n"),
             program_name, program_name, program_name,
             program_name, program_name, program_name,
             program_name, program_name, program_name);
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

  set_up_terminal ();

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

  /* If developing, add ./appliance to the path.  Note that libtools
   * interferes with this because uninstalled guestfish is a shell
   * script that runs the real program with an absolute path.  Detect
   * that too.
   *
   * BUT if LIBGUESTFS_PATH environment variable is already set by
   * the user, then don't override it.
   */
  if (getenv ("LIBGUESTFS_PATH") == NULL &&
      argv[0] &&
      (argv[0][0] != '/' || strstr (argv[0], "/.libs/lt-") != NULL))
    guestfs_set_path (g, "appliance:" GUESTFS_DEFAULT_PATH);

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

  /* Decide if we display progress bars. */
  progress_bars =
    override_progress_bars >= 0
    ? override_progress_bars
    : (optind >= argc && isatty (0));

  if (progress_bars)
    guestfs_set_event_callback (g, progress_callback,
                                GUESTFS_EVENT_PROGRESS, 0, NULL);

  /* Interactive, shell script, or command(s) on the command line? */
  if (optind >= argc) {
    if (isatty (0))
      interactive ();
    else
      shell_script ();
  }
  else
    cmdline (argv, optind, argc);

  cleanup_readline ();

  exit (EXIT_SUCCESS);
}

/* The <term.h> header file which defines this has "issues". */
extern int tgetent (char *, const char *);

static void
set_up_terminal (void)
{
  /* http://www.cl.cam.ac.uk/~mgk25/unicode.html#activate */
  utf8_mode = STREQ (nl_langinfo (CODESET), "UTF-8");

  char *term = getenv ("TERM");
  if (term == NULL) {
    //fprintf (stderr, _("guestfish: TERM (terminal type) not defined.\n"));
    return;
  }

  int r = tgetent (NULL, term);
  if (r == -1) {
    fprintf (stderr, _("guestfish: could not access termcap or terminfo database.\n"));
    return;
  }
  if (r == 0) {
    fprintf (stderr, _("guestfish: terminal type \"%s\" not defined.\n"),
             term);
    return;
  }

  have_terminfo = 1;
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
      len = strcspn (p, "\"");
      if (p[len] == '\0') {
        fprintf (stderr, _("%s: unterminated double quote\n"), program_name);
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

  if (pclose (pp) == -1) {
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

  reset_progress_bar ();

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

/* Resolve the special "win:..." form for Windows-specific paths.
 * This always returns a newly allocated string which is freed by the
 * caller function in "cmds.c".
 */
char *
resolve_win_path (const char *path)
{
  char *ret;
  size_t i;

  if (STRCASENEQLEN (path, "win:", 4)) {
    ret = strdup (path);
    if (ret == NULL)
      perror ("strdup");
    return ret;
  }

  path += 4;

  /* Drop drive letter, if it's "C:". */
  if (STRCASEEQLEN (path, "c:", 2))
    path += 2;

  if (!*path) {
    ret = strdup ("/");
    if (ret == NULL)
      perror ("strdup");
    return ret;
  }

  ret = strdup (path);
  if (ret == NULL) {
    perror ("strdup");
    return NULL;
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
