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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>

#include <guestfs.h>

#include "fish.h"

struct mp {
  struct mp *next;
  char *device;
  char *mountpoint;
};

static void mount_mps (struct mp *mp);
static void interactive (void);
static void shell_script (void);
static void script (int prompt);
static void cmdline (char *argv[], int optind, int argc);
static void issue_command (const char *cmd, char *argv[]);

/* Currently open libguestfs handle. */
guestfs_h *g;
int g_launched = 0;

int quit = 0;

void
launch (void)
{
  if (!g_launched) {
    if (guestfs_launch (g) == -1)
      exit (1);
    if (guestfs_wait_ready (g) == -1)
      exit (1);
    g_launched = 1;
  }
}

static void
usage (void)
{
  fprintf (stderr,
	   "guestfish: guest filesystem shell\n"
	   "guestfish lets you edit virtual machine filesystems\n"
	   "Copyright (C) 2009 Red Hat Inc.\n"
	   "Usage:\n"
	   "  guestfish [--options] cmd [: cmd ...]\n"
	   "or for interactive use:\n"
	   "  guestfish\n"
	   "or from a shell script:\n"
	   "  guestfish <<EOF\n"
	   "  cmd\n"
	   "  ...\n"
	   "  EOF\n"
	   "Options:\n"
	   "  -h|--cmd-help       List available commands\n"
	   "  -h|--cmd-help cmd   Display detailed help on 'cmd'\n"
	   "  -a image            Add image\n"
	   "  -m dev[:mnt]        Mount dev on mnt (if omitted, /)\n"
	   /*"  --ro|-r             All mounts are read-only\n"*/
	   "  -v|--verbose        Verbose messages\n"
	   "For more information, see the manpage guestfish(1).\n");
}

int
main (int argc, char *argv[])
{
  static const char *options = "a:h::m:v?";
  static struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "cmd-help", 2, 0, 'h' },
    { "help", 0, 0, '?' },
    { "mount", 1, 0, 'm' },
    { "verbose", 0, 0, 'v' },
    { 0, 0, 0, 0 }
  };
  struct mp *mps = NULL;
  struct mp *mp;
  char *p;
  int c;

  /* guestfs_create is meant to be a lightweight operation, so
   * it's OK to do it early here.
   */
  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, "guestfs_create: failed to create handle\n");
    exit (1);
  }

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case 'a':
      if (access (optarg, R_OK) != 0) {
	perror (optarg);
	exit (1);
      }
      if (guestfs_add_drive (g, optarg) == -1)
	exit (1);
      break;

    case 'h':
      if (optarg)
	display_command (optarg);
      else if (argv[optind] && argv[optind][0] != '-')
	display_command (argv[optind++]);
      else
	list_commands ();
      exit (0);

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
	mp->mountpoint = "/";
      mp->device = optarg;
      mp->next = mps;
      mps = mp->next;
      break;

    case '?':
      usage ();
      exit (0);

    default:
      fprintf (stderr, "guestfish: unexpected command line option 0x%x\n", c);
      exit (1);
    }
  }

  /* If we've got mountpoints, we must launch the guest and mount them. */
  if (mps != NULL) {
    launch ();
    mount_mps (mps);
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

  exit (0);
}

void
pod2text (const char *heading, const char *str)
{
  FILE *fp;

  fp = popen ("pod2text", "w");
  if (fp == NULL) {
    /* pod2text failed, maybe not found, so let's just print the
     * source instead, since that's better than doing nothing.
     */
    printf ("%s\n\n%s\n", heading, str);
    return;
  }
  fputs ("=head1 ", fp);
  fputs (heading, fp);
  fputs ("\n\n", fp);
  fputs (str, fp);
  pclose (fp);
}

/* List is built in reverse order, so mount them in reverse order. */
static void
mount_mps (struct mp *mp)
{
  if (mp) {
    mount_mps (mp->next);
    if (guestfs_mount (g, mp->device, mp->mountpoint) == -1)
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

static void
script (int prompt)
{
  char buf[8192];
  char *cmd;
  char *argv[64];
  int len, i;

  if (prompt)
    printf ("Welcome to guestfish, the libguestfs filesystem interactive shell for\n"
	    "editing virtual machine filesystems.\n"
	    "\n"
	    "Type: 'help' for help with commands\n"
	    "      'quit' to quit the shell\n"
	    "\n");

  while (!quit) {
    if (prompt) printf ("><fs> ");
    if (fgets (buf, sizeof buf, stdin) == NULL) {
      quit = 1;
      break;
    }

    len = strlen (buf);
    if (len > 0 && buf[len-1] == '\n') buf[len-1] = '\0';

    /* Split the buffer up at whitespace. */
    cmd = strtok (buf, " \t");
    if (cmd == NULL)
      continue;

    i = 0;
    while (i < sizeof argv / sizeof argv[0] &&
	   (argv[i] = strtok (NULL, " \t")) != NULL)
      i++;
    if (i == sizeof argv / sizeof argv[0]) {
      fprintf (stderr, "guestfish: too many arguments in command\n");
      exit (1);
    }

    issue_command (cmd, argv);
  }
  if (prompt) printf ("\n");
}

static void
cmdline (char *argv[], int optind, int argc)
{
  const char *cmd;
  char **params;

  if (optind >= argc) return;

  cmd = argv[optind++];
  if (strcmp (cmd, ":") == 0) {
    fprintf (stderr, "guestfish: empty command on command line\n");
    exit (1);
  }
  params = &argv[optind];

  /* Search for end of command list or ":" ... */
  while (optind < argc && strcmp (argv[optind], ":") != 0)
    optind++;

  if (optind == argc)
    issue_command (cmd, params);
  else {
    argv[optind] = NULL;
    issue_command (cmd, params);
    cmdline (argv, optind+1, argc);
  }
}

static void
issue_command (const char *cmd, char *argv[])
{
  int i;

  fprintf (stderr, "cmd = %s", cmd);
  for (i = 0; argv[i] != NULL; ++i)
    fprintf (stderr, ", arg[%d]=%s", i, argv[i]);
  fprintf (stderr, "\n");





}
