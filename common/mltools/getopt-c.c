/* argument parsing using getopt(3)
 * Copyright (C) 2016 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <stdbool.h>
#include <libintl.h>
#include <errno.h>
#include <error.h>
#include <assert.h>

#include "xstrtol.h"
#include "getprogname.h"

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/callback.h>
#include <caml/printexc.h>

#include "guestfs-utils.h"

extern value guestfs_int_mllib_getopt_parse (value argsv, value specsv, value anon_funv, value usage_msgv);

#define Val_none Val_int(0)

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE_OPTION_LIST __attribute__((cleanup(cleanup_option_list)))

static void
cleanup_option_list (void *ptr)
{
  struct option *opts = * (struct option **) ptr;
  struct option *p = opts;

  while (p->name != NULL) {
    /* Cast the constness away, since we created the names on heap. */
    free ((char *) p->name);
    ++p;
  }
  free (opts);
}

#else
#define CLEANUP_FREE_OPTION_LIST
#endif

static void __attribute__((noreturn))
show_error (int status)
{
  fprintf (stderr, _("Try ‘%s --help’ or consult %s(1) for more information.\n"),
           getprogname (), getprogname ());
  exit (status);
}

static int
find_spec (value specsv, int specs_len, char opt)
{
  CAMLparam1 (specsv);
  CAMLlocal1 (keysv);
  int i, ret;

  for (i = 0; i < specs_len; ++i) {
    int len, j;

    keysv = Field (Field (specsv, i), 0);
    len = Wosize_val (keysv);

    for (j = 0; j < len; ++j) {
      const char *key = String_val (Field (keysv, j));

      if (key[0] == '-' && key[1] == opt) {
        ret = i;
        goto done;
      }
    }
  }

  ret = -1;

 done:
  CAMLreturnT (int, ret);
}

static bool
list_mem (value listv, const char *val)
{
  CAMLparam1 (listv);
  CAMLlocal1 (hd);
  bool found = false;

  while (listv != Val_emptylist) {
    hd = Field (listv, 0);
    if (STREQ (String_val (hd), val)) {
      found = true;
      break;
    }
    listv = Field (listv, 1);
  }

  CAMLreturnT (bool, found);
}

static bool
vector_has_dashdash_opt (value vectorv, const char *opt)
{
  CAMLparam1 (vectorv);
  bool found = false;
  int len, i;

  len = Wosize_val (vectorv);

  for (i = 0; i < len; ++i) {
    const char *key = String_val (Field (vectorv, i));

    ++key;
    if (key[0] == '-')
      ++key;

    if (STREQ (opt, key)) {
      found = true;
      break;
    }
  }

  CAMLreturnT (bool, found);
}

static void
list_print (FILE *stream, value listv)
{
  CAMLparam1 (listv);
  CAMLlocal1 (hd);
  bool first = true;

  while (listv != Val_emptylist) {
    hd = Field (listv, 0);
    if (!first)
      fprintf (stream, ", ");
    fprintf (stream, "%s", String_val (hd));
    first = false;
    listv = Field (listv, 1);
  }

  CAMLreturn0;
}

static void
do_call1 (value funv, value paramv)
{
  CAMLparam2 (funv, paramv);
  CAMLlocal1 (rv);

  rv = caml_callback_exn (funv, paramv);

  if (Is_exception_result (rv))
    fprintf (stderr,
             "libguestfs: uncaught OCaml exception in getopt callback: %s\n",
             caml_format_exception (Extract_exception (rv)));

  CAMLreturn0;
}

static int
strtoint (const char *arg)
{
  long int num;

  if (xstrtol (arg, NULL, 0, &num, "") != LONGINT_OK) {
    fprintf (stderr, _("%s: ‘%s’ is not a numeric value.\n"),
             getprogname (), arg);
    show_error (EXIT_FAILURE);
  }

  if (num < -(1<<30) || num > (1<<30)-1) {
    fprintf (stderr, _("%s: %s: integer out of range\n"),
             getprogname (), arg);
    show_error (EXIT_FAILURE);
  }

  return (int) num;
}

value
guestfs_int_mllib_getopt_parse (value argsv, value specsv, value anon_funv, value usage_msgv)
{
  CAMLparam4 (argsv, specsv, anon_funv, usage_msgv);
  CAMLlocal5 (specv, keysv, actionv, v, v2);
  size_t argc;
  CLEANUP_FREE_STRING_LIST char **argv = NULL;
  size_t specs_len, i;
  CLEANUP_FREE char *optstring = NULL;
  int optstring_len = 0;
  CLEANUP_FREE_OPTION_LIST struct option *longopts = NULL;
  int longopts_len = 0;
  int c;
  int specv_index;

  argc = Wosize_val (argsv);
  argv = malloc (sizeof (char *) * (argc + 1));
  if (argv == NULL)
    caml_raise_out_of_memory ();
  for (i = 0; i < argc; ++i) {
    argv[i] = strdup (String_val (Field (argsv, i)));
    if (argv[i] == NULL)
      caml_raise_out_of_memory ();
  }
  argv[argc] = NULL;

  specs_len = Wosize_val (specsv);

  optstring = malloc (1);
  if (optstring == NULL)
    caml_raise_out_of_memory ();
  longopts = malloc (sizeof (*longopts));
  if (longopts == NULL)
    caml_raise_out_of_memory ();

  for (i = 0; i < specs_len; ++i) {
    size_t len, j;

    specv = Field (specsv, i);
    keysv = Field (specv, 0);
    actionv = Field (specv, 1);
    len = Wosize_val (keysv);

    assert (len != 0);

    for (j = 0; j < len; ++j) {
      const char *key = String_val (Field (keysv, j));
      const size_t key_len = strlen (key);
      int has_arg = 0;

      /* We assume that the key is valid, with the checks done in the
       * OCaml Getopt.parse_argv. */
      ++key;
      if (key[0] == '-')
        ++key;

      switch (Tag_val (actionv)) {
      case 0:  /* Unit of (unit -> unit) */
      case 1:  /* Set of bool ref */
      case 2:  /* Clear of bool ref */
        has_arg = 0;
        break;

      case 3:  /* String of string * (string -> unit) */
      case 4:  /* Set_string of string * string ref */
      case 5:  /* Int of string * (int -> unit) */
      case 6:  /* Set_int of string * int ref */
      case 7:  /* Symbol of string * string list * (string -> unit) */
        has_arg = 1;
        break;

      case 8:  /* OptString of string * (string option -> unit) */
        has_arg = 2;
        break;

      default:
        error (EXIT_FAILURE, 0,
               "internal error: unhandled Tag_val (actionv) = %d",
               Tag_val (actionv));
      }

      if (key_len == 2) {  /* Single letter short option. */
        char *newstring = realloc (optstring, optstring_len + 1 + has_arg + 1);
        if (newstring == NULL)
          caml_raise_out_of_memory ();
        optstring = newstring;
        optstring[optstring_len++] = key[0];
        if (has_arg > 0) {
          optstring[optstring_len++] = ':';
          if (has_arg > 1)
            optstring[optstring_len++] = ':';
        }
      } else {
        struct option *newopts = realloc (longopts, (longopts_len + 1 + 1) * sizeof (*longopts));
        if (newopts == NULL)
          caml_raise_out_of_memory ();
        longopts = newopts;
        longopts[longopts_len].name = strdup (key);
        if (longopts[longopts_len].name == NULL)
          caml_raise_out_of_memory ();
        longopts[longopts_len].has_arg = has_arg;
        longopts[longopts_len].flag = &specv_index;
        longopts[longopts_len].val = i;
        ++longopts_len;
      }
    }
  }

  /* Zero entries at the end. */
  optstring[optstring_len] = 0;
  longopts[longopts_len].name = NULL;
  longopts[longopts_len].has_arg = 0;
  longopts[longopts_len].flag = NULL;
  longopts[longopts_len].val = 0;

  for (;;) {
    int option_index = -1;
    c = getopt_long_only (argc, argv, optstring, longopts, &option_index);
    if (c == -1) break;

    switch (c) {
    case '?':
      show_error (EXIT_FAILURE);
      break;

    case 0:
      /* specv_index set already -- nothing to do. */
      break;

    default:
      specv_index = find_spec (specsv, specs_len, c);
      break;
    }

    specv = Field (specsv, specv_index);
    actionv = Field (specv, 1);

    switch (Tag_val (actionv)) {
    int num;

    case 0:  /* Unit of (unit -> unit) */
      v = Field (actionv, 0);
      do_call1 (v, Val_unit);
      break;

    case 1:  /* Set of bool ref */
      caml_modify (&Field (Field (actionv, 0), 0), Val_true);
      break;

    case 2:  /* Clear of bool ref */
      caml_modify (&Field (Field (actionv, 0), 0), Val_false);
      break;

    case 3:  /* String of string * (string -> unit) */
      v = Field (actionv, 1);
      v2 = caml_copy_string (optarg);
      do_call1 (v, v2);
      break;

    case 4:  /* Set_string of string * string ref */
      v = caml_copy_string (optarg);
      caml_modify (&Field (Field (actionv, 1), 0), v);
      break;

    case 5:  /* Int of string * (int -> unit) */
      num = strtoint (optarg);
      v = Field (actionv, 1);
      do_call1 (v, Val_int (num));
      break;

    case 6:  /* Set_int of string * int ref */
      num = strtoint (optarg);
      caml_modify (&Field (Field (actionv, 1), 0), Val_int (num));
      break;

    case 7:  /* Symbol of string * string list * (string -> unit) */
      v = Field (actionv, 1);
      if (!list_mem (v, optarg)) {
        if (c != 0) {
          fprintf (stderr, _("%s: ‘%s’ is not allowed for -%c; allowed values are:\n"),
                   getprogname (), optarg, c);
        } else {
          fprintf (stderr, _("%s: ‘%s’ is not allowed for %s%s; allowed values are:\n"),
                   getprogname (), optarg,
                   vector_has_dashdash_opt (specv, longopts[option_index].name) ? "--" : "-",
                   longopts[option_index].name);
        }
        fprintf (stderr, "  ");
        list_print (stderr, v);
        fprintf (stderr, "\n");
        show_error (EXIT_FAILURE);
      }
      v = Field (actionv, 2);
      v2 = caml_copy_string (optarg);
      do_call1 (v, v2);
      break;

    case 8:  /* OptString of string * (string option -> unit) */
      v = Field (actionv, 1);
      if (optarg) {
        v2 = caml_alloc (1, 0);
        Store_field (v2, 0, caml_copy_string (optarg));
      } else {
        v2 = Val_none;
      }
      do_call1 (v, v2);
      break;

    default:
      error (EXIT_FAILURE, 0,
             "internal error: unhandled Tag_val (actionv) = %d",
             Tag_val (actionv));
    }
  }

  if (optind < (int) argc) {
    if (anon_funv == Val_none) {
      fprintf (stderr, _("Extra parameter on the command line: ‘%s’.\n"),
               argv[optind]);
      show_error (EXIT_FAILURE);
    }
    v = Field (anon_funv, 0);
    while (optind < (int) argc) {
      v2 = caml_copy_string (argv[optind++]);
      do_call1 (v, v2);
    }
  }

  CAMLreturn (Val_unit);
}
