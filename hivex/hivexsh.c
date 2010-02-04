/* hivexsh - Hive shell.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <assert.h>
#include <errno.h>

#ifdef HAVE_LIBREADLINE
#include <readline/readline.h>
#include <readline/history.h>
#endif

#ifdef HAVE_GETTEXT
#include "gettext.h"
#define _(str) dgettext(PACKAGE, (str))
//#define N_(str) dgettext(PACKAGE, (str))
#else
#define _(str) str
//#define N_(str) str
#endif

#define STREQ(a,b) (strcmp((a),(b)) == 0)
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
//#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
//#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
//#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
//#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
//#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)

#include "c-ctype.h"
#include "xstrtol.h"

#include "hivex.h"
#include "byte_conversions.h"

static int quit = 0;
static int is_tty;
static hive_h *h = NULL;
static char *prompt_string = NULL; /* Normal prompt string. */
static char *loaded = NULL;     /* Basename of loaded file, if any. */
static hive_node_h cwd;         /* Current node. */
static int open_flags = 0;      /* Flags used when loading a hive file. */

static void usage (void) __attribute__((noreturn));
static void print_node_path (hive_node_h, FILE *);
static void set_prompt_string (void);
static void initialize_readline (void);
static void cleanup_readline (void);
static void add_history_line (const char *);
static char *rl_gets (const char *prompt_string);
static void sort_strings (char **strings, int len);
static int get_xdigit (char c);
static int dispatch (char *cmd, char *args);
static int cmd_cd (char *path);
static int cmd_close (char *path);
static int cmd_commit (char *path);
static int cmd_del (char *args);
static int cmd_help (char *args);
static int cmd_load (char *hivefile);
static int cmd_ls (char *args);
static int cmd_lsval (char *args);
static int cmd_setval (char *args);

static void
usage (void)
{
  fprintf (stderr, "hivexsh [-dfw] [hivefile]\n");
  exit (EXIT_FAILURE);
}

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  int c;
  const char *filename = NULL;

  set_prompt_string ();

  while ((c = getopt (argc, argv, "dfw")) != EOF) {
    switch (c) {
    case 'd':
      open_flags |= HIVEX_OPEN_DEBUG;
      break;
    case 'f':
      filename = optarg;
      break;
    case 'w':
      open_flags |= HIVEX_OPEN_WRITE;
      break;
    default:
      usage ();
    }
  }

  if (optind < argc) {
    if (optind + 1 != argc)
      usage ();
    if (cmd_load (argv[optind]) == -1)
      exit (EXIT_FAILURE);
  }

  /* -f filename parameter */
  if (filename) {
    close (0);
    if (open (filename, O_RDONLY) == -1) {
      perror (filename);
      exit (EXIT_FAILURE);
    }
  }

  /* Main loop. */
  is_tty = isatty (0);
  initialize_readline ();

  if (is_tty)
    printf (_(
"\n"
"Welcome to hivexsh, the hivex interactive shell for examining\n"
"Windows Registry binary hive files.\n"
"\n"
"Type: 'help' for help summary\n"
"      'quit' to quit the shell\n"
"\n"));

  while (!quit) {
    char *buf = rl_gets (prompt_string);
    if (!buf) {
      quit = 1;
      if (is_tty)
        printf ("\n");
      break;
    }

    while (*buf && c_isspace (*buf))
      buf++;

    /* Ignore blank line. */
    if (!*buf) continue;

    /* If the next character is '#' then this is a comment. */
    if (*buf == '#') continue;

    /* Parsing is very simple - much simpler than guestfish.  This is
     * because Registry keys often contain spaces, and we don't want
     * to bother with quoting.  Therefore here we just split at the
     * first whitespace into "cmd<whitespace>arg(s)".  We let the
     * command decide how to deal with arg(s), if at all.
     */
    size_t len = strcspn (buf, " \t");

    if (len == 0) continue;

    char *cmd = buf;
    char *args;
    size_t i = 0;

    if (buf[len] == '\0') {
      /* This is mostly safe.  Although the cmd_* functions do sometimes
       * modify args, then shouldn't do so when args is "".
       */
      args = (char *) "";
      goto got_command;
    }

    buf[len] = '\0';
    args = buf + len + 1 + strspn (&buf[len+1], " \t");

    len = strlen (args);
    while (len > 0 && c_isspace (args[len-1])) {
      args[len-1] = '\0';
      len--;
    }

  got_command:
    /*printf ("command: '%s'  args: '%s'\n", cmd, args)*/;
    int r = dispatch (cmd, args);
    if (!is_tty && r == -1)
      exit (EXIT_FAILURE);
  }

  cleanup_readline ();
  free (prompt_string);
  free (loaded);
  if (h) hivex_close (h);
  exit (0);
}

/* Set the prompt string.  This is called whenever it could change, eg.
 * after loading a file or changing directory.
 */
static void
set_prompt_string (void)
{
  free (prompt_string);
  prompt_string = NULL;

  FILE *fp;
  char *ptr;
  size_t size;
  fp = open_memstream (&ptr, &size);
  if (fp == NULL) {
    perror ("open_memstream");
    exit (EXIT_FAILURE);
  }

  if (h) {
    assert (loaded != NULL);
    assert (cwd != 0);

    fputs (loaded, fp);
    print_node_path (cwd, fp);
  }

  fprintf (fp, "> ");
  fclose (fp);
  prompt_string = ptr;
}

/* Print the \full\path of a node. */
static void
print_node_path (hive_node_h node, FILE *fp)
{
  hive_node_h root = hivex_root (h);

  if (node == root) {
    fputc ('\\', fp);
    return;
  }

  hive_node_h parent = hivex_node_parent (h, node);
  if (parent == 0) {
    fprintf (stderr, _("hivexsh: error getting parent of node %zu\n"), node);
    return;
  }
  print_node_path (parent, fp);

  if (parent != root)
    fputc ('\\', fp);

  char *name = hivex_node_name (h, node);
  if (name == NULL) {
    fprintf (stderr, _("hivexsh: error getting node name of node %zx\n"), node);
    return;
  }

  fputs (name, fp);
  free (name);
}

static char *line_read = NULL;

static char *
rl_gets (const char *prompt_string)
{
#ifdef HAVE_LIBREADLINE

  if (is_tty) {
    if (line_read) {
      free (line_read);
      line_read = NULL;
    }

    line_read = readline (prompt_string);

    if (line_read && *line_read)
      add_history_line (line_read);

    return line_read;
  }

#endif /* HAVE_LIBREADLINE */

  static char buf[8192];
  int len;

  if (is_tty)
    printf ("%s", prompt_string);
  line_read = fgets (buf, sizeof buf, stdin);

  if (line_read) {
    len = strlen (line_read);
    if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';
  }

  return line_read;
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
    snprintf (histfile, sizeof histfile, "%s/.hivexsh", home);
    using_history ();
    (void) read_history (histfile);
  }

  rl_readline_name = "hivexsh";
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

static int
compare (const void *vp1, const void *vp2)
{
  char * const *p1 = (char * const *) vp1;
  char * const *p2 = (char * const *) vp2;
  return strcasecmp (*p1, *p2);
}

static void
sort_strings (char **strings, int len)
{
  qsort (strings, len, sizeof (char *), compare);
}

static int
get_xdigit (char c)
{
  switch (c) {
  case '0'...'9': return c - '0';
  case 'a'...'f': return c - 'a' + 10;
  case 'A'...'F': return c - 'A' + 10;
  default: return -1;
  }
}

static int
dispatch (char *cmd, char *args)
{
  if (STRCASEEQ (cmd, "help"))
    return cmd_help (args);
  else if (STRCASEEQ (cmd, "load"))
    return cmd_load (args);
  else if (STRCASEEQ (cmd, "exit") ||
           STRCASEEQ (cmd, "q") ||
           STRCASEEQ (cmd, "quit")) {
    quit = 1;
    return 0;
  }

  /* If no hive file is loaded (!h) then only the small selection of
   * commands above will work.
   */
  if (!h) {
    fprintf (stderr, _("hivexsh: you must load a hive file first using 'load hivefile'\n"));
    return -1;
  }

  if (STRCASEEQ (cmd, "cd"))
    return cmd_cd (args);
  else if (STRCASEEQ (cmd, "close") || STRCASEEQ (cmd, "unload"))
    return cmd_close (args);
  else if (STRCASEEQ (cmd, "commit"))
    return cmd_commit (args);
  else if (STRCASEEQ (cmd, "del"))
    return cmd_del (args);
  else if (STRCASEEQ (cmd, "ls"))
    return cmd_ls (args);
  else if (STRCASEEQ (cmd, "lsval"))
    return cmd_lsval (args);
  else if (STRCASEEQ (cmd, "setval"))
    return cmd_setval (args);
  else {
    fprintf (stderr, _("hivexsh: unknown command '%s', use 'help' for help summary\n"),
             cmd);
    return -1;
  }
}

static int
cmd_load (char *hivefile)
{
  if (STREQ (hivefile, "")) {
    fprintf (stderr, _("hivexsh: load: no hive file name given to load\n"));
    return -1;
  }

  if (h) hivex_close (h);
  h = NULL;

  free (loaded);
  loaded = NULL;

  cwd = 0;

  h = hivex_open (hivefile, open_flags);
  if (h == NULL) {
    fprintf (stderr,
             _(
"hivexsh: failed to open hive file: %s: %m\n"
"\n"
"If you think this file is a valid Windows binary hive file (_not_\n"
"a regedit *.reg file) then please run this command again using the\n"
"hivexsh option '-d' and attach the complete output _and_ the hive file\n"
"which fails into a bug report at https://bugzilla.redhat.com/\n"
"\n"),
             hivefile);
    return -1;
  }

  /* Get the basename of the file for the prompt. */
  char *p = strrchr (hivefile, '/');
  if (p)
    loaded = strdup (p+1);
  else
    loaded = strdup (hivefile);
  if (!loaded) {
    perror ("strdup");
    exit (EXIT_FAILURE);
  }

  cwd = hivex_root (h);

  set_prompt_string ();

  return 0;
}

static int
cmd_close (char *args)
{
  if (STRNEQ (args, "")) {
    fprintf (stderr, _("hivexsh: '%s' command should not be given arguments\n"),
             "close");
    return -1;
  }

  if (h) hivex_close (h);
  h = NULL;

  free (loaded);
  loaded = NULL;

  cwd = 0;

  set_prompt_string ();

  return 0;
}

static int
cmd_commit (char *path)
{
  if (STREQ (path, ""))
    path = NULL;

  if (hivex_commit (h, path, 0) == -1) {
    perror ("hivexsh: commit");
    return -1;
  }

  return 0;
}

static int
cmd_cd (char *path)
{
  if (STREQ (path, "")) {
    print_node_path (cwd, stdout);
    fputc ('\n', stdout);
    return 0;
  }

  if (path[0] == '\\' && path[1] == '\\') {
    fprintf (stderr, _("%s: %s: \\ characters in path are doubled - are you escaping the path parameter correctly?\n"), "hivexsh", path);
    return -1;
  }

  hive_node_h new_cwd = cwd;
  hive_node_h root = hivex_root (h);

  if (path[0] == '\\') {
    new_cwd = root;
    path++;
  }

  while (path[0]) {
    size_t len = strcspn (path, "\\");
    if (len == 0) {
      path++;
      continue;
    }

    char *elem = path;
    path = path[len] == '\0' ? &path[len] : &path[len+1];
    elem[len] = '\0';

    if (len == 1 && STREQ (elem, "."))
      continue;

    if (len == 2 && STREQ (elem, "..")) {
      if (new_cwd != root)
        new_cwd = hivex_node_parent (h, new_cwd);
      continue;
    }

    errno = 0;
    new_cwd = hivex_node_get_child (h, new_cwd, elem);
    if (new_cwd == 0) {
      if (errno)
        perror ("hivexsh: cd");
      else
        fprintf (stderr, _("hivexsh: cd: subkey '%s' not found\n"),
                 elem);
      return -1;
    }
  }

  if (new_cwd != cwd) {
    cwd = new_cwd;
    set_prompt_string ();
  }

  return 0;
}

static int
cmd_help (char *args)
{
  printf (_(
"Navigate through the hive's keys using the 'cd' command, as if it\n"
"contained a filesystem, and use 'ls' to list the subkeys of the\n"
"current key.  Full documentation is in the hivexsh(1) manual page.\n"));

  return 0;
}

static int
cmd_ls (char *args)
{
  if (STRNEQ (args, "")) {
    fprintf (stderr, _("hivexsh: '%s' command should not be given arguments\n"),
             "ls");
    return -1;
  }

  /* Get the subkeys. */
  hive_node_h *children = hivex_node_children (h, cwd);
  if (children == NULL) {
    perror ("ls");
    return -1;
  }

  /* Get names for each subkey. */
  size_t len;
  for (len = 0; children[len] != 0; ++len)
    ;

  char **names = calloc (len, sizeof (char *));
  if (names == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }

  int ret = -1;
  size_t i;
  for (i = 0; i < len; ++i) {
    names[i] = hivex_node_name (h, children[i]);
    if (names[i] == NULL) {
      perror ("hivex_node_name");
      goto error;
    }
  }

  /* Sort the names. */
  sort_strings (names, len);

  for (i = 0; i < len; ++i)
    printf ("%s\n", names[i]);

  ret = 0;
 error:
  free (children);
  for (i = 0; i < len; ++i)
    free (names[i]);
  free (names);
  return ret;
}

static int
cmd_lsval (char *key)
{
  if (STRNEQ (key, "")) {
    hive_value_h value;

    errno = 0;
    if (STREQ (key, "@"))       /* default key written as "@" */
      value = hivex_node_get_value (h, cwd, "");
    else
      value = hivex_node_get_value (h, cwd, key);

    if (value == 0) {
      if (errno)
        goto error;
      /* else key not found */
      fprintf (stderr, _("%s: %s: key not found\n"), "hivexsh", key);
      return -1;
    }

    /* Print the value. */
    hive_type t;
    size_t len;
    if (hivex_value_type (h, value, &t, &len) == -1)
      goto error;

    switch (t) {
    case hive_t_string:
    case hive_t_expand_string:
    case hive_t_link: {
      char *str = hivex_value_string (h, value);
      if (!str)
        goto error;

      puts (str); /* note: this adds a single \n character */
      free (str);
      break;
    }

    case hive_t_dword:
    case hive_t_dword_be: {
      int32_t j = hivex_value_dword (h, value);
      printf ("%" PRIi32 "\n", j);
      break;
    }

    case hive_t_qword: {
      int64_t j = hivex_value_qword (h, value);
      printf ("%" PRIi64 "\n", j);
      break;
    }

    case hive_t_multiple_strings: {
      char **strs = hivex_value_multiple_strings (h, value);
      if (!strs)
        goto error;
      size_t j;
      for (j = 0; strs[j] != NULL; ++j) {
        puts (strs[j]);
        free (strs[j]);
      }
      free (strs);
      break;
    }

    case hive_t_none:
    case hive_t_binary:
    case hive_t_resource_list:
    case hive_t_full_resource_description:
    case hive_t_resource_requirements_list:
    default: {
      char *data = hivex_value_value (h, value, &t, &len);
      if (!data)
        goto error;

      if (fwrite (data, 1, len, stdout) != len)
        goto error;

      free (data);
      break;
    }
    } /* switch */
  } else {
    /* No key specified, so print all keys in this node.  We do this
     * in a format which looks like the output of regedit, although
     * this isn't a particularly useful format.
     */
    hive_value_h *values;

    values = hivex_node_values (h, cwd);
    if (values == NULL)
      goto error;

    size_t i;
    for (i = 0; values[i] != 0; ++i) {
      char *key = hivex_value_key (h, values[i]);
      if (!key) goto error;

      if (*key) {
        putchar ('"');
        size_t j;
        for (j = 0; key[j] != 0; ++j) {
          if (key[j] == '"' || key[j] == '\\')
            putchar ('\\');
          putchar (key[j]);
        }
        putchar ('"');
      } else
        printf ("\"@\"");       /* default key in regedit files */
      putchar ('=');
      free (key);

      hive_type t;
      size_t len;
      if (hivex_value_type (h, values[i], &t, &len) == -1)
        goto error;

      switch (t) {
      case hive_t_string:
      case hive_t_expand_string:
      case hive_t_link: {
        char *str = hivex_value_string (h, values[i]);
        if (!str)
          goto error;

        if (t != hive_t_string)
          printf ("str(%d):", t);
        putchar ('"');
        size_t j;
        for (j = 0; str[j] != 0; ++j) {
          if (str[j] == '"' || str[j] == '\\')
            putchar ('\\');
          putchar (str[j]);
        }
        putchar ('"');
        free (str);
        break;
      }

      case hive_t_dword:
      case hive_t_dword_be: {
        int32_t j = hivex_value_dword (h, values[i]);
        printf ("dword:%08" PRIx32, j);
        break;
      }

      case hive_t_qword: /* sic */
      case hive_t_none:
      case hive_t_binary:
      case hive_t_multiple_strings:
      case hive_t_resource_list:
      case hive_t_full_resource_description:
      case hive_t_resource_requirements_list:
      default: {
        char *data = hivex_value_value (h, values[i], &t, &len);
        if (!data)
          goto error;

        printf ("hex(%d):", t);
        size_t j;
        for (j = 0; j < len; ++j) {
          if (j > 0)
            putchar (',');
          printf ("%02x", data[j]);
        }
        break;
      }
      } /* switch */

      putchar ('\n');
    } /* for */

    free (values);
  }

  return 0;

 error:
  perror ("hivexsh: lsval");
  return -1;
}

static int
cmd_setval (char *nrvals_str)
{
  strtol_error xerr;

  /* Parse number of values. */
  long nrvals;
  xerr = xstrtol (nrvals_str, NULL, 0, &nrvals, "");
  if (xerr != LONGINT_OK) {
    fprintf (stderr, _("%s: %s: invalid integer parameter (%s returned %d)\n"),
             "setval", "nrvals", "xstrtol", xerr);
    return -1;
  }
  if (nrvals < 0 || nrvals > 1000) {
    fprintf (stderr, _("%s: %s: integer out of range\n"),
             "setval", "nrvals");
    return -1;
  }

  struct hive_set_value *values =
    calloc (nrvals, sizeof (struct hive_set_value));
  if (values == NULL) {
    perror ("calloc");
    exit (EXIT_FAILURE);
  }

  int ret = -1;

  /* Read nrvals * 2 lines of input, nrvals * (key, value) pairs, as
   * explained in the man page.
   */
  int prompt = isatty (0) ? 2 : 0;
  int i, j;
  for (i = 0; i < nrvals; ++i) {
    /* Read key. */
    char *buf = rl_gets ("  key> ");
    if (!buf) {
      fprintf (stderr, _("hivexsh: setval: unexpected end of input\n"));
      quit = 1;
      goto error;
    }

    /* Note that buf will be overwritten by the next call to rl_gets. */
    if (STREQ (buf, "@"))
      values[i].key = strdup ("");
    else
      values[i].key = strdup (buf);
    if (values[i].key == NULL) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }

    /* Read value. */
    buf = rl_gets ("value> ");
    if (!buf) {
      fprintf (stderr, _("hivexsh: setval: unexpected end of input\n"));
      quit = 1;
      goto error;
    }

    if (STREQ (buf, "none")) {
      values[i].t = hive_t_none;
      values[i].len = 0;
    }
    else if (STRPREFIX (buf, "string:")) {
      buf += 7;
      values[i].t = hive_t_string;
      int nr_chars = strlen (buf);
      values[i].len = 2 * (nr_chars + 1);
      values[i].value = malloc (values[i].len);
      if (!values[i].value) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      for (j = 0; j <= /* sic */ nr_chars; ++j) {
        if (buf[j] & 0x80) {
          fprintf (stderr, _("hivexsh: string(utf16le): only 7 bit ASCII strings are supported for input\n"));
          goto error;
        }
        values[i].value[2*j] = buf[j];
        values[i].value[2*j+1] = '\0';
      }
    }
    else if (STRPREFIX (buf, "expandstring:")) {
      buf += 13;
      values[i].t = hive_t_string;
      int nr_chars = strlen (buf);
      values[i].len = 2 * (nr_chars + 1);
      values[i].value = malloc (values[i].len);
      if (!values[i].value) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      for (j = 0; j <= /* sic */ nr_chars; ++j) {
        if (buf[j] & 0x80) {
          fprintf (stderr, _("hivexsh: string(utf16le): only 7 bit ASCII strings are supported for input\n"));
          goto error;
        }
        values[i].value[2*j] = buf[j];
        values[i].value[2*j+1] = '\0';
      }
    }
    else if (STRPREFIX (buf, "dword:")) {
      buf += 6;
      values[i].t = hive_t_dword;
      values[i].len = 4;
      values[i].value = malloc (4);
      if (!values[i].value) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      long n;
      xerr = xstrtol (buf, NULL, 0, &n, "");
      if (xerr != LONGINT_OK) {
        fprintf (stderr, _("%s: %s: invalid integer parameter (%s returned %d)\n"),
                 "setval", "dword", "xstrtol", xerr);
        goto error;
      }
      if (n < 0 || n > UINT32_MAX) {
        fprintf (stderr, _("%s: %s: integer out of range\n"),
                 "setval", "dword");
        goto error;
      }
      uint32_t u32 = htole32 (n);
      memcpy (values[i].value, &u32, 4);
    }
    else if (STRPREFIX (buf, "qword:")) {
      buf += 6;
      values[i].t = hive_t_qword;
      values[i].len = 8;
      values[i].value = malloc (8);
      if (!values[i].value) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      long long n;
      xerr = xstrtoll (buf, NULL, 0, &n, "");
      if (xerr != LONGINT_OK) {
        fprintf (stderr, _("%s: %s: invalid integer parameter (%s returned %d)\n"),
                 "setval", "dword", "xstrtoll", xerr);
        goto error;
      }
#if 0
      if (n < 0 || n > UINT64_MAX) {
        fprintf (stderr, _("%s: %s: integer out of range\n"),
                 "setval", "dword");
        goto error;
      }
#endif
      uint64_t u64 = htole64 (n);
      memcpy (values[i].value, &u64, 4);
    }
    else if (STRPREFIX (buf, "hex:")) {
      /* Read the type. */
      buf += 4;
      size_t len = strcspn (buf, ":");
      char *nextbuf;
      if (buf[len] == '\0')     /* "hex:t" */
        nextbuf = &buf[len];
      else {                    /* "hex:t:..." */
        buf[len] = '\0';
        nextbuf = &buf[len+1];
      }

      long t;
      xerr = xstrtol (buf, NULL, 0, &t, "");
      if (xerr != LONGINT_OK) {
        fprintf (stderr, _("%s: %s: invalid integer parameter (%s returned %d)\n"),
                 "setval", "hex", "xstrtol", xerr);
        goto error;
      }
      if (t < 0 || t > UINT32_MAX) {
        fprintf (stderr, _("%s: %s: integer out of range\n"),
                 "setval", "hex");
        goto error;
      }
      values[i].t = t;

      /* Read the hex data. */
      buf = nextbuf;

      /* The allocation length is an overestimate, but it doesn't matter. */
      values[i].value = malloc (1 + strlen (buf) / 2);
      if (!values[i].value) {
        perror ("malloc");
        exit (EXIT_FAILURE);
      }
      values[i].len = 0;

      while (*buf) {
        int c = 0;

        for (j = 0; *buf && j < 2; buf++) {
          if (c_isxdigit (*buf)) { /* NB: ignore non-hex digits. */
            c <<= 4;
            c |= get_xdigit (*buf);
            j++;
          }
        }

        if (j == 2) values[i].value[values[i].len++] = c;
        else if (j == 1) {
          fprintf (stderr, _("hivexsh: setval: trailing garbage after hex string\n"));
          goto error;
        }
      }
    }
    else {
      fprintf (stderr,
               _("hivexsh: setval: cannot parse value string, please refer to the man page hivexsh(1) for help: %s\n"),
               buf);
      goto error;
    }
  }

  ret = hivex_node_set_values (h, cwd, nrvals, values, 0);

 error:
  /* Free values array. */
  for (i = 0; i < nrvals; ++i) {
    free (values[i].key);
    free (values[i].value);
  }
  free (values);

  return ret;
}

static int
cmd_del (char *args)
{
  if (STRNEQ (args, "")) {
    fprintf (stderr, _("hivexsh: '%s' command should not be given arguments\n"),
             "del");
    return -1;
  }

  if (cwd == hivex_root (h)) {
    fprintf (stderr, _("hivexsh: del: the root node cannot be deleted\n"));
    return -1;
  }

  hive_node_h new_cwd = hivex_node_parent (h, cwd);

  if (hivex_node_delete_child (h, cwd) == -1) {
    perror ("hivexsh: del");
    return -1;
  }

  cwd = new_cwd;
  set_prompt_string ();
  return 0;
}
