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

/* Test the library can be loaded and unloaded using dlopen etc. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dlfcn.h>
#include <errno.h>
#include <error.h>

/* We don't need the <guestfs.h> header file here. */
typedef struct guestfs_h guestfs_h;

typedef guestfs_h *(*guestfs_create_t) (void);
typedef const char * (*guestfs_get_program_t) (guestfs_h *);
typedef void (*guestfs_close_t) (guestfs_h *);

#ifndef LIBRARY
#error "-DLIBRARY was not defined"
#endif

static void *
read_symbol (void *lib, const char *symbol)
{
  void *symval;
  const char *err;

  dlerror (); /* Clear error indicator. */
  symval = dlsym (lib, symbol);
  if ((err = dlerror ()) != NULL)
    error (EXIT_FAILURE, 0,
           "could not read symbol: %s: %s", symbol, err);
  return symval;
}

int
main (int argc, char *argv[])
{
  void *lib;
  guestfs_create_t guestfs_create;
  guestfs_get_program_t guestfs_get_program;
  guestfs_close_t guestfs_close;
  guestfs_h *g;

  if (access (LIBRARY, X_OK) == -1)
    error (77, errno, "test skipped because %s cannot be accessed", LIBRARY);

  lib = dlopen (LIBRARY, RTLD_LAZY);
  if (lib == NULL)
    error (EXIT_FAILURE, 0, "could not open %s: %s", LIBRARY, dlerror ());

  guestfs_create = read_symbol (lib, "guestfs_create");
  guestfs_get_program = read_symbol (lib, "guestfs_get_program");
  guestfs_close = read_symbol (lib, "guestfs_close");

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");
  printf ("program = %s\n", guestfs_get_program (g));

  guestfs_close (g);

  if (dlclose (lib) != 0)
    error (EXIT_FAILURE, 0, "could not close %s: %s", LIBRARY, dlerror ());

  exit (EXIT_SUCCESS);
}
