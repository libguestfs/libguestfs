/* guestfish - the filesystem interactive shell
 * Copyright (C) 2009 Red Hat Inc.
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

#define _GNU_SOURCE // for strchrnul

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include <signal.h>
#include <assert.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/wait.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#include <readline/history.h>
#endif

#include <guestfs.h>

#include "fish.h"

struct mp {
  struct mp *next;
  char *device;
  char *mountpoint;
};

struct drv {
  struct drv *next;
  char *filename;
};

static void add_drives (struct drv *drv);
static void mount_mps (struct mp *mp);
static void interactive (void);
static void shell_script (void);
static void script (int prompt);
static void cmdline (char *argv[], int optind, int argc);
static void initialize_readline (void);
static void cleanup_readline (void);
static void add_history_line (const char *);

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 0;
int quit = 0;
int verbose = 0;
int echo_commands = 0;
int remote_control_listen = 0;
int remote_control = 0;
int exit_on_error = 1;

int
launch (guestfs_h *_g)
{
  assert (_g == g);

  if (guestfs_is_config (g)) {
    if (guestfs_launch (g) == -1)
      return -1;
    if (guestfs_wait_ready (g) == -1)
      return -1;
  }
  return 0;
}

static void
usage (void)
{
  fprintf (stderr,
           _("guestfish: guest filesystem shell\n"
             "guestfish lets you edit virtual machine filesystems\n"
             "Copyright (C) 2009 Red Hat Inc.\n"
             "Usage:\n"
             "  guestfish [--options] cmd [: cmd : cmd ...]\n"
             "  guestfish -i libvirt-domain\n"
             "  guestfish -i disk-image(s)\n"
             "or for interactive use:\n"
             "  guestfish\n"
             "or from a shell script:\n"
             "  guestfish <<EOF\n"
             "  cmd\n"
             "  ...\n"
             "  EOF\n"
             "Options:\n"
             "  -h|--cmd-help        List available commands\n"
             "  -h|--cmd-help cmd    Display detailed help on 'cmd'\n"
             "  -a|--add image       Add image\n"
             "  -D|--no-dest-paths   Don't tab-complete paths from guest fs\n"
             "  -f|--file file       Read commands from file\n"
             "  -i|--inspector       Run virt-inspector to get disk mountpoints\n"
             "  --listen             Listen for remote commands\n"
             "  -m|--mount dev[:mnt] Mount dev on mnt (if omitted, /)\n"
             "  -n|--no-sync         Don't autosync\n"
             "  --remote[=pid]       Send commands to remote guestfish\n"
             "  -r|--ro              Mount read-only\n"
             "  --selinux            Enable SELinux support\n"
             "  -v|--verbose         Verbose messages\n"
             "  -x                   Echo each command before executing it\n"
             "  -V|--version         Display version and exit\n"
             "For more information,  see the manpage guestfish(1).\n"));
}

int
main (int argc, char *argv[])
{
  static const char *options = "a:Df:h::im:nrv?Vx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "cmd-help", 2, 0, 'h' },
    { "file", 1, 0, 'f' },
    { "help", 0, 0, '?' },
    { "inspector", 0, 0, 'i' },
    { "listen", 0, 0, 0 },
    { "mount", 1, 0, 'm' },
    { "no-dest-paths", 0, 0, 'D' },
    { "no-sync", 0, 0, 'n' },
    { "remote", 2, 0, 0 },
    { "ro", 0, 0, 'r' },
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
  int c;
  int inspector = 0;
  int option_index;
  struct sigaction sa;

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
    exit (1);
  }

  guestfs_set_autosync (g, 1);

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

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (strcmp (long_options[option_index].name, "listen") == 0)
        remote_control_listen = 1;
      else if (strcmp (long_options[option_index].name, "remote") == 0) {
        if (optarg) {
          if (sscanf (optarg, "%d", &remote_control) != 1) {
            fprintf (stderr, _("guestfish: --listen=PID: PID was not a number: %s\n"), optarg);
            exit (1);
          }
        } else {
          p = getenv ("GUESTFISH_PID");
          if (!p || sscanf (p, "%d", &remote_control) != 1) {
            fprintf (stderr, _("guestfish: remote: $GUESTFISH_PID must be set to the PID of the remote process\n"));
            exit (1);
          }
        }
      } else if (strcmp (long_options[option_index].name, "selinux") == 0) {
        guestfs_set_selinux (g, 1);
      } else {
        fprintf (stderr, _("guestfish: unknown long option: %s (%d)\n"),
                 long_options[option_index].name, option_index);
        exit (1);
      }
      break;

    case 'a':
      if (access (optarg, R_OK) != 0) {
        perror (optarg);
        exit (1);
      }
      drv = malloc (sizeof (struct drv));
      if (!drv) {
        perror ("malloc");
        exit (1);
      }
      drv->filename = optarg;
      drv->next = drvs;
      drvs = drv;
      break;

    case 'D':
      complete_dest_paths = 0;
      break;

    case 'f':
      if (file) {
        fprintf (stderr, _("guestfish: only one -f parameter can be given\n"));
        exit (1);
      }
      file = optarg;
      break;

    case 'h':
      if (optarg)
        display_command (optarg);
      else if (argv[optind] && argv[optind][0] != '-')
        display_command (argv[optind++]);
      else
        list_commands ();
      exit (0);

    case 'i':
      inspector = 1;
      break;

    case 'm':
      mp = malloc (sizeof (struct mp));
      if (!mp) {
        perror ("malloc");
        exit (1);
      }
      p = strchr (optarg, ':');
      if (p) {
        *p = '\0';
        mp->mountpoint = p+1;
      } else
        mp->mountpoint = bad_cast ("/");
      mp->device = optarg;
      mp->next = mps;
      mps = mp;
      break;

    case 'n':
      guestfs_set_autosync (g, 0);
      break;

    case 'r':
      read_only = 1;
      break;

    case 'v':
      verbose++;
      guestfs_set_verbose (g, verbose);
      break;

    case 'V':
      printf ("guestfish %s\n", PACKAGE_VERSION);
      exit (0);

    case 'x':
      echo_commands = 1;
      break;

    case '?':
      usage ();
      exit (0);

    default:
      fprintf (stderr, _("guestfish: unexpected command line option 0x%x\n"),
               c);
      exit (1);
    }
  }

  /* Inspector mode invalidates most of the other arguments. */
  if (inspector) {
    char cmd[1024];
    int r;

    if (drvs || mps || remote_control_listen || remote_control ||
        guestfs_get_selinux (g)) {
      fprintf (stderr, _("guestfish: cannot use -i option with -a, -m, --listen, --remote or --selinux\n"));
      exit (1);
    }
    if (optind >= argc) {
      fprintf (stderr, _("guestfish -i requires a libvirt domain or path(s) to disk image(s)\n"));
      exit (1);
    }

    strcpy (cmd, "a=`virt-inspector");
    while (optind < argc) {
      if (strlen (cmd) + strlen (argv[optind]) + strlen (argv[0]) + 60
          >= sizeof cmd) {
        fprintf (stderr, _("guestfish: virt-inspector command too long for fixed-size buffer\n"));
        exit (1);
      }
      strcat (cmd, " '");
      strcat (cmd, argv[optind]);
      strcat (cmd, "'");
      optind++;
    }

    if (read_only)
      strcat (cmd, " --ro-fish");
    else
      strcat (cmd, " --fish");

    sprintf (&cmd[strlen(cmd)], "` && %s $a", argv[0]);

    if (guestfs_get_verbose (g))
      strcat (cmd, " -v");
    if (!guestfs_get_autosync (g))
      strcat (cmd, " -n");

    if (verbose)
      fprintf (stderr,
               "guestfish -i: running virt-inspector command:\n%s\n", cmd);

    r = system (cmd);
    if (r == -1) {
      perror ("system");
      exit (1);
    }
    exit (WEXITSTATUS (r));
  }

  /* If we've got drives to add, add them now. */
  add_drives (drvs);

  /* If we've got mountpoints, we must launch the guest and mount them. */
  if (mps != NULL) {
    if (launch (g) == -1) exit (1);
    mount_mps (mps);
  }

  /* Remote control? */
  if (remote_control_listen && remote_control) {
    fprintf (stderr, _("guestfish: cannot use --listen and --remote options at the same time\n"));
    exit (1);
  }

  if (remote_control_listen) {
    if (optind < argc) {
      fprintf (stderr, _("guestfish: extra parameters on the command line with --listen flag\n"));
      exit (1);
    }
    if (file) {
      fprintf (stderr, _("guestfish: cannot use --listen and --file options at the same time\n"));
      exit (1);
    }
    rc_listen ();
  }

  /* -f (file) parameter? */
  if (file) {
    close (0);
    if (open (file, O_RDONLY) == -1) {
      perror (file);
      exit (1);
    }
  }

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

  exit (0);
}

void
pod2text (const char *name, const char *shortdesc, const char *str)
{
  FILE *fp;

  fp = popen ("pod2text", "w");
  if (fp == NULL) {
    /* pod2text failed, maybe not found, so let's just print the
     * source instead, since that's better than doing nothing.
     */
    printf ("%s - %s\n\n%s\n", name, shortdesc, str);
    return;
  }
  fprintf (fp, "=head1 %s - %s\n\n", name, shortdesc);
  fputs (str, fp);
  pclose (fp);
}

/* List is built in reverse order, so mount them in reverse order. */
static void
mount_mps (struct mp *mp)
{
  int r;

  if (mp) {
    mount_mps (mp->next);
    if (!read_only)
      r = guestfs_mount (g, mp->device, mp->mountpoint);
    else
      r = guestfs_mount_ro (g, mp->device, mp->mountpoint);
    if (r == -1)
      exit (1);
  }
}

static void
add_drives (struct drv *drv)
{
  int r;

  if (drv) {
    add_drives (drv->next);
    if (!read_only)
      r = guestfs_add_drive (g, drv->filename);
    else
      r = guestfs_add_drive_ro (g, drv->filename);
    if (r == -1)
      exit (1);
  }
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
  char *cmd;
  char *p, *pend;
  char *argv[64];
  int len;
  int global_exit_on_error = !prompt;
  int tilde_candidate;

  if (prompt)
    printf (_("\n"
              "Welcome to guestfish, the libguestfs filesystem interactive shell for\n"
              "editing virtual machine filesystems.\n"
              "\n"
              "Type: 'help' for help with commands\n"
              "      'quit' to quit the shell\n"
              "\n"));

  while (!quit) {
    char *pipe = NULL;

    exit_on_error = global_exit_on_error;

    buf = rl_gets (prompt);
    if (!buf) {
      quit = 1;
      break;
    }

    /* Skip any initial whitespace before the command. */
  again:
    while (*buf && isspace (*buf))
      buf++;

    if (!*buf) continue;

    /* If the next character is '#' then this is a comment. */
    if (*buf == '#') continue;

    /* If the next character is '!' then pass the whole lot to system(3). */
    if (*buf == '!') {
      int r;

      r = system (buf+1);
      if (exit_on_error) {
        if (r == -1 ||
            (WIFSIGNALED (r) &&
             (WTERMSIG (r) == SIGINT || WTERMSIG (r) == SIGQUIT)) ||
            WEXITSTATUS (r) != 0)
          exit (1);
      }
      continue;
    }

    /* If the next character is '-' allow the command to fail without
     * exiting on error (just for this one command though).
     */
    if (*buf == '-') {
      exit_on_error = 0;
      buf++;
      goto again;
    }

    /* Get the command (cannot be quoted). */
    len = strcspn (buf, " \t");

    if (len == 0) continue;

    cmd = buf;
    unsigned int i = 0;
    if (buf[len] == '\0') {
      argv[0] = NULL;
      goto got_command;
    }

    buf[len] = '\0';
    p = &buf[len+1];
    p += strspn (p, " \t");

    /* Get the parameters. */
    while (*p && i < sizeof argv / sizeof argv[0]) {
      tilde_candidate = 0;

      /* Parameters which start with quotes or pipes are treated
       * specially.  Bare parameters are delimited by whitespace.
       */
      if (*p == '"') {
        p++;
        len = strcspn (p, "\"");
        if (p[len] == '\0') {
          fprintf (stderr, _("guestfish: unterminated double quote\n"));
          if (exit_on_error) exit (1);
          goto next_command;
        }
        if (p[len+1] && (p[len+1] != ' ' && p[len+1] != '\t')) {
          fprintf (stderr, _("guestfish: command arguments not separated by whitespace\n"));
          if (exit_on_error) exit (1);
          goto next_command;
        }
        p[len] = '\0';
        pend = p[len+1] ? &p[len+2] : &p[len+1];
      } else if (*p == '\'') {
        p++;
        len = strcspn (p, "'");
        if (p[len] == '\0') {
          fprintf (stderr, _("guestfish: unterminated single quote\n"));
          if (exit_on_error) exit (1);
          goto next_command;
        }
        if (p[len+1] && (p[len+1] != ' ' && p[len+1] != '\t')) {
          fprintf (stderr, _("guestfish: command arguments not separated by whitespace\n"));
          if (exit_on_error) exit (1);
          goto next_command;
        }
        p[len] = '\0';
        pend = p[len+1] ? &p[len+2] : &p[len+1];
      } else if (*p == '|') {
        *p = '\0';
        pipe = p+1;
        continue;
        /*
      } else if (*p == '[') {
        int c = 1;
        p++;
        pend = p;
        while (*pend && c != 0) {
          if (*pend == '[') c++;
          else if (*pend == ']') c--;
          pend++;
        }
        if (c != 0) {
          fprintf (stderr, _("guestfish: unterminated \"[...]\" sequence\n"));
          if (exit_on_error) exit (1);
          goto next_command;
        }
        if (*pend && (*pend != ' ' && *pend != '\t')) {
          fprintf (stderr, _("guestfish: command arguments not separated by whitespace\n"));
          if (exit_on_error) exit (1);
          goto next_command;
        }
        *(pend-1) = '\0';
        */
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
        fprintf (stderr, _("guestfish: internal error parsing string at '%s'\n"),
                 p);
        abort ();
      }

      if (!tilde_candidate)
        argv[i] = p;
      else
        argv[i] = try_tilde_expansion (p);
      i++;
      p = pend;

      if (*p)
        p += strspn (p, " \t");
    }

    if (i == sizeof argv / sizeof argv[0]) {
      fprintf (stderr, _("guestfish: too many arguments\n"));
      if (exit_on_error) exit (1);
      goto next_command;
    }

    argv[i] = NULL;

  got_command:
    if (issue_command (cmd, argv, pipe) == -1) {
      if (exit_on_error) exit (1);
    }

  next_command:;
  }
  if (prompt) printf ("\n");
}

static void
cmdline (char *argv[], int optind, int argc)
{
  const char *cmd;
  char **params;

  exit_on_error = 1;

  if (optind >= argc) return;

  cmd = argv[optind++];
  if (strcmp (cmd, ":") == 0) {
    fprintf (stderr, _("guestfish: empty command on command line\n"));
    exit (1);
  }
  params = &argv[optind];

  /* Search for end of command list or ":" ... */
  while (optind < argc && strcmp (argv[optind], ":") != 0)
    optind++;

  if (optind == argc) {
    if (issue_command (cmd, params, NULL) == -1) exit (1);
  } else {
    argv[optind] = NULL;
    if (issue_command (cmd, params, NULL) == -1) exit (1);
    cmdline (argv, optind+1, argc);
  }
}

int
issue_command (const char *cmd, char *argv[], const char *pipecmd)
{
  int argc;
  int stdout_saved_fd = -1;
  int pid = 0;
  int i, r;

  if (echo_commands) {
    printf ("%s", cmd);
    for (i = 0; argv[i] != NULL; ++i)
      printf (" %s", argv[i]);
    printf ("\n");
  }

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
    r = rc_remote (remote_control, cmd, argc, argv, exit_on_error);

  /* Otherwise execute it locally. */
  else if (strcasecmp (cmd, "help") == 0) {
    if (argc == 0)
      list_commands ();
    else
      display_command (argv[0]);
    r = 0;
  }
  else if (strcasecmp (cmd, "quit") == 0 ||
           strcasecmp (cmd, "exit") == 0 ||
           strcasecmp (cmd, "q") == 0) {
    quit = 1;
    r = 0;
  }
  else if (strcasecmp (cmd, "alloc") == 0 ||
           strcasecmp (cmd, "allocate") == 0)
    r = do_alloc (cmd, argc, argv);
  else if (strcasecmp (cmd, "echo") == 0)
    r = do_echo (cmd, argc, argv);
  else if (strcasecmp (cmd, "edit") == 0 ||
           strcasecmp (cmd, "vi") == 0 ||
           strcasecmp (cmd, "emacs") == 0)
    r = do_edit (cmd, argc, argv);
  else if (strcasecmp (cmd, "lcd") == 0)
    r = do_lcd (cmd, argc, argv);
  else if (strcasecmp (cmd, "glob") == 0)
    r = do_glob (cmd, argc, argv);
  else if (strcasecmp (cmd, "more") == 0 ||
           strcasecmp (cmd, "less") == 0)
    r = do_more (cmd, argc, argv);
  else if (strcasecmp (cmd, "reopen") == 0)
    r = do_reopen (cmd, argc, argv);
  else if (strcasecmp (cmd, "time") == 0)
    r = do_time (cmd, argc, argv);
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

  printf ("%-20s %s\n",
          "alloc", _("allocate an image"));
  printf ("%-20s %s\n",
          "echo", _("display a line of text"));
  printf ("%-20s %s\n",
          "edit", _("edit a file in the image"));
  printf ("%-20s %s\n",
          "lcd", _("local change directory"));
  printf ("%-20s %s\n",
          "glob", _("expand wildcards in command"));
  printf ("%-20s %s\n",
          "more", _("view a file in the pager"));
  printf ("%-20s %s\n",
          "reopen", _("close and reopen libguestfs handle"));
  printf ("%-20s %s\n",
          "time", _("measure time taken to run command"));

  /* actions are printed after this (see list_commands) */
}

void
display_builtin_command (const char *cmd)
{
  /* help for actions is auto-generated, see display_command */

  if (strcasecmp (cmd, "alloc") == 0 ||
      strcasecmp (cmd, "allocate") == 0)
    printf (_("alloc - allocate an image\n"
              "     alloc <filename> <size>\n"
              "\n"
              "    This creates an empty (zeroed) file of the given size,\n"
              "    and then adds so it can be further examined.\n"
              "\n"
              "    For more advanced image creation, see qemu-img utility.\n"
              "\n"
              "    Size can be specified (where <nn> means a number):\n"
              "    <nn>             number of kilobytes\n"
              "      eg: 1440       standard 3.5\" floppy\n"
              "    <nn>K or <nn>KB  number of kilobytes\n"
              "    <nn>M or <nn>MB  number of megabytes\n"
              "    <nn>G or <nn>GB  number of gigabytes\n"
              "    <nn>sects        number of 512 byte sectors\n"));
  else if (strcasecmp (cmd, "echo") == 0)
    printf (_("echo - display a line of text\n"
              "     echo [<params> ...]\n"
              "\n"
              "    This echos the parameters to the terminal.\n"));
  else if (strcasecmp (cmd, "edit") == 0 ||
           strcasecmp (cmd, "vi") == 0 ||
           strcasecmp (cmd, "emacs") == 0)
    printf (_("edit - edit a file in the image\n"
              "     edit <filename>\n"
              "\n"
              "    This is used to edit a file.\n"
              "\n"
              "    It is the equivalent of (and is implemented by)\n"
              "    running \"cat\", editing locally, and then \"write-file\".\n"
              "\n"
              "    Normally it uses $EDITOR, but if you use the aliases\n"
              "    \"vi\" or \"emacs\" you will get those editors.\n"
              "\n"
              "    NOTE: This will not work reliably for large files\n"
              "    (> 2 MB) or binary files containing \\0 bytes.\n"));
  else if (strcasecmp (cmd, "lcd") == 0)
    printf (_("lcd - local change directory\n"
              "    lcd <directory>\n"
              "\n"
              "    Change guestfish's current directory. This command is\n"
              "    useful if you want to download files to a particular\n"
              "    place.\n"));
  else if (strcasecmp (cmd, "glob") == 0)
    printf (_("glob - expand wildcards in command\n"
              "    glob <command> [<args> ...]\n"
              "\n"
              "    Glob runs <command> with wildcards expanded in any\n"
              "    command args.  Note that the command is run repeatedly\n"
              "    once for each expanded argument.\n"));
  else if (strcasecmp (cmd, "help") == 0)
    printf (_("help - display a list of commands or help on a command\n"
              "     help cmd\n"
              "     help\n"));
  else if (strcasecmp (cmd, "more") == 0 ||
           strcasecmp (cmd, "less") == 0)
    printf (_("more - view a file in the pager\n"
              "     more <filename>\n"
              "\n"
              "    This is used to view a file in the pager.\n"
              "\n"
              "    It is the equivalent of (and is implemented by)\n"
              "    running \"cat\" and using the pager.\n"
              "\n"
              "    Normally it uses $PAGER, but if you use the alias\n"
              "    \"less\" then it always uses \"less\".\n"
              "\n"
              "    NOTE: This will not work reliably for large files\n"
              "    (> 2 MB) or binary files containing \\0 bytes.\n"));
  else if (strcasecmp (cmd, "quit") == 0 ||
           strcasecmp (cmd, "exit") == 0 ||
           strcasecmp (cmd, "q") == 0)
    printf (_("quit - quit guestfish\n"
              "     quit\n"));
  else if (strcasecmp (cmd, "reopen") == 0)
    printf (_("reopen - close and reopen the libguestfs handle\n"
              "     reopen\n"
              "\n"
              "Close and reopen the libguestfs handle.  It is not necessary to use\n"
              "this normally, because the handle is closed properly when guestfish\n"
              "exits.  However this is occasionally useful for testing.\n"));
  else if (strcasecmp (cmd, "time") == 0)
    printf (_("time - measure time taken to run command\n"
              "    time <command> [<args> ...]\n"
              "\n"
              "    This runs <command> as usual, and prints the elapsed\n"
              "    time afterwards.\n"));
  else
    fprintf (stderr, _("%s: command not known, use -h to list all commands\n"),
             cmd);
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
    strcasecmp (str, "0") != 0 &&
    strcasecmp (str, "f") != 0 &&
    strcasecmp (str, "false") != 0 &&
    strcasecmp (str, "n") != 0 &&
    strcasecmp (str, "no") != 0;
}

/* XXX We could improve list parsing. */
char **
parse_string_list (const char *str)
{
  char **argv;
  const char *p, *pend;
  int argc, i;

  argc = 1;
  for (i = 0; str[i]; ++i)
    if (str[i] == ' ') argc++;

  argv = malloc (sizeof (char *) * (argc+1));
  if (argv == NULL) { perror ("malloc"); exit (1); }

  p = str;
  i = 0;
  while (*p) {
    pend = strchrnul (p, ' ');
    argv[i] = strndup (p, pend-p);
    i++;
    p = *pend == ' ' ? pend+1 : pend;
  }
  argv[i] = NULL;

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

    (void) append_history (nr_history_lines, histfile);
  }
#endif
}

static void
add_history_line (const char *line)
{
#ifdef HAVE_LIBREADLINE
  add_history (line);
  nr_history_lines++;
#endif
}

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
