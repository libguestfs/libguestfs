/* hivexget - Get single subkeys or values from a hive.
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
#include <errno.h>

#include "hivex.h"

int
main (int argc, char *argv[])
{
  if (argc < 3 || argc > 4) {
    fprintf (stderr, "hivexget regfile path [key]\n");
    exit (EXIT_FAILURE);
  }
  char *file = argv[1];
  char *path = argv[2];
  char *key = argv[3];          /* could be NULL */

  if (path[0] != '\\') {
    fprintf (stderr, "hivexget: path must start with a \\ character\n");
    exit (EXIT_FAILURE);
  }
  if (path[1] == '\\') {
  doubled:
    fprintf (stderr, "hivexget: %s: \\ characters in path are doubled - are you escaping the path parameter correctly?\n", path);
    exit (EXIT_FAILURE);
  }

  hive_h *h = hivex_open (file, 0);
  if (h == NULL) {
  error:
    perror (file);
    exit (EXIT_FAILURE);
  }

  /* Navigate to the desired node. */
  hive_node_h node = hivex_root (h);
  if (!node)
    goto error;

  char *p = path+1, *pnext;
  size_t len;
  while (*p) {
    len = strcspn (p, "\\");

    if (len == 0)
      goto doubled;

    if (p[len] == '\\') {
      p[len] = '\0';
      pnext = p + len + 1;
    } else
      pnext = p + len;

    errno = 0;
    node = hivex_node_get_child (h, node, p);
    if (node == 0) {
      if (errno)
        goto error;
      /* else node not found */
      fprintf (stderr, "hivexget: %s: %s: path element not found\n",
               path, p);
      exit (2);
    }

    p = pnext;
  }

  /* Get the desired key, or print all keys. */
  if (key) {
    hive_value_h value;

    errno = 0;
    if (key[0] == '@' && key[1] == '\0') /* default key written as "@" */
      value = hivex_node_get_value (h, node, "");
    else
      value = hivex_node_get_value (h, node, key);

    if (value == 0) {
      if (errno)
        goto error;
      /* else key not found */
      fprintf (stderr, "hivexget: %s: key not found\n", key);
      exit (2);
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

    values = hivex_node_values (h, node);
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
        printf ("dword:%08" PRIx32 "\"", j);
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

  if (hivex_close (h) == -1)
    goto error;

  exit (EXIT_SUCCESS);
}
