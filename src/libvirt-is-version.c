/* libguestfs
 * Copyright (C) 2014 Red Hat Inc.
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
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <locale.h>
#include <libintl.h>

#include <libvirt/libvirt.h>

static unsigned int argtoint (const char *prog, const char *arg);

int
main (int argc, char *argv[])
{
  unsigned long ver;
  unsigned int major = 0, minor = 0, release = 0;

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  switch (argc) {
  case 4:
    release = argtoint (argv[0], argv[3]);
    /*FALLTHROUGH*/
  case 3:
    minor = argtoint (argv[0], argv[2]);
    /*FALLTHROUGH*/
  case 2:
    major = argtoint (argv[0], argv[1]);
    break;
  case 1:
    error (EXIT_FAILURE, 0, "not enough arguments: MAJOR [MINOR [PATCH]]");
  }

  virInitialize ();

  if (virGetVersion (&ver, NULL, NULL) == -1)
    exit (EXIT_FAILURE);

  return ver >= (major * 1000000 + minor * 1000 + release)
    ? EXIT_SUCCESS : EXIT_FAILURE;
}

static unsigned int
argtoint (const char *prog, const char *arg)
{
  long int res;
  char *endptr;

  errno = 0;
  res = strtol (arg, &endptr, 10);
  if (errno || *endptr)
    error (EXIT_FAILURE, 0, "cannot parse integer argument '%s'", arg);

  return (unsigned int) res;
}
