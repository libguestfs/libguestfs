/* guestfish - the filesystem shell
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

static void
usage (void)
{
  fprintf (stderr,
	   "guestfish: guest filesystem shell\n"
	   "guestfish lets you edit virtual machine filesystems\n"
	   "Copyright (C) 2009 Red Hat Inc.\n"
	   "Usage:\n"
	   "  guestfish [--options] [cmd]\n"
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
	   "For more information, see the manual page guestfish(1).\n");
}

int
main (int argc, char *argv[])
{
  static const char *options = "h::?";
  static struct option long_options[] = {
    { "cmd-help", 2, 0, 'h' },
    { "help", 0, 0, '?' },
    { 0, 0, 0, 0 }
  };
  int c;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case 'h':
      if (optarg)
	display_command (optarg);
      else if (argv[optind] && argv[optind][0] != '-')
	display_command (argv[optind++]);
      else
	list_commands ();
      exit (0);

    case '?':
      usage ();
      exit (0);

    default:
      fprintf (stderr, "guestfish: unexpected command line option 0x%x\n", c);
      exit (1);
    }
  }

  if (optind < argc) {
    usage ();
    exit (1);
  }












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
