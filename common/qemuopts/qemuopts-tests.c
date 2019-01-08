/* libguestfs
 * Copyright (C) 2014-2019 Red Hat Inc.
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

/**
 * Unit tests of internal functions.
 *
 * These tests may use a libguestfs handle, but must not launch the
 * handle.  Also, avoid long-running tests.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#include "qemuopts.h"

#define CHECK_ERROR(r,call,expr)                \
  do {                                          \
    if ((expr) == (r)) {                        \
      perror (call);                            \
      exit (EXIT_FAILURE);                      \
    }                                           \
  } while (0)

int
main (int argc, char *argv[])
{
  struct qemuopts *qopts;
  FILE *fp;
  char *actual;
  size_t i, len;
  char **actual_argv;

  qopts = qemuopts_create ();

  if (qemuopts_set_binary_by_arch (qopts, NULL) == -1) {
    if (errno == ENXIO) {
      fprintf (stderr, "qemuopts: This architecture does not support KVM.\n");
      fprintf (stderr, "If this architecture *does* support KVM, then please modify qemuopts.c\n");
      fprintf (stderr, "and send us a patch.\n");
      exit (77);                /* Skip the test. */
    }
    perror ("qemuopts_set_binary_by_arch");
    exit (EXIT_FAILURE);
  }
  /* ... but for the purposes of testing, it's easier if we
   * set this to a known string.
   */
  CHECK_ERROR (-1, "qemuopts_set_binary",
               qemuopts_set_binary (qopts, "qemu-system-x86_64"));

  CHECK_ERROR (-1, "qemuopts_add_flag",
               qemuopts_add_flag (qopts, "-no-user-config"));
  CHECK_ERROR (-1, "qemuopts_add_arg",
               qemuopts_add_arg (qopts, "-m", "1024"));
  CHECK_ERROR (-1, "qemuopts_add_arg_format",
               qemuopts_add_arg_format (qopts, "-smp", "%d", 4));

  CHECK_ERROR (-1, "qemuopts_start_arg_list",
               qemuopts_start_arg_list (qopts, "-drive"));
  CHECK_ERROR (-1, "qemuopts_append_arg_list",
               qemuopts_append_arg_list (qopts, "file=/tmp/foo"));
  CHECK_ERROR (-1, "qemuopts_append_arg_list_format",
               qemuopts_append_arg_list_format (qopts, "if=%s", "ide"));
  CHECK_ERROR (-1, "qemuopts_end_arg_list",
               qemuopts_end_arg_list (qopts));
  CHECK_ERROR (-1, "qemuopts_add_arg_list",
               qemuopts_add_arg_list (qopts, "-drive",
                                      "file=/tmp/bar", "serial=123",
                                      NULL));

  /* Test qemu comma-quoting. */
  CHECK_ERROR (-1, "qemuopts_add_arg",
               qemuopts_add_arg (qopts, "-name", "foo,bar"));
  CHECK_ERROR (-1, "qemuopts_add_arg_list",
               qemuopts_add_arg_list (qopts, "-drive",
                                      "file=comma,in,name",
                                      "serial=$dollar$",
                                      NULL));

  /* Test shell quoting. */
  CHECK_ERROR (-1, "qemuopts_add_arg",
               qemuopts_add_arg (qopts, "-cdrom", "\"$quoted\".iso"));

  fp = open_memstream (&actual, &len);
  if (fp == NULL) {
    perror ("open_memstream");
    exit (EXIT_FAILURE);
  }
  CHECK_ERROR (-1, "qemuopts_to_channel",
               qemuopts_to_channel (qopts, fp));
  if (fclose (fp) == EOF) {
    perror ("fclose");
    exit (EXIT_FAILURE);
  }

  const char *expected =
    "qemu-system-x86_64 \\\n"
    "    -no-user-config \\\n"
    "    -m 1024 \\\n"
    "    -smp 4 \\\n"
    "    -drive file=/tmp/foo,if=ide \\\n"
    "    -drive file=/tmp/bar,serial=123 \\\n"
    "    -name \"foo,,bar\" \\\n"
    "    -drive \"file=comma,,in,,name\",\"serial=\\$dollar\\$\" \\\n"
    "    -cdrom \"\\\"\\$quoted\\\".iso\"\n";

  if (strcmp (actual, expected) != 0) {
    fprintf (stderr, "qemuopts: Serialized qemu command line does not match expected\n");
    fprintf (stderr, "Actual:\n%s", actual);
    fprintf (stderr, "Expected:\n%s", expected);
    exit (EXIT_FAILURE);
  }

  free (actual);

  /* Test qemuopts_to_argv. */
  CHECK_ERROR (NULL, "qemuopts_to_argv",
               actual_argv = qemuopts_to_argv (qopts));
  const char *expected_argv[] = {
    "qemu-system-x86_64",
    "-no-user-config",
    "-m", "1024",
    "-smp", "4",
    "-drive", "file=/tmp/foo,if=ide",
    "-drive", "file=/tmp/bar,serial=123",
    "-name", "foo,,bar",
    "-drive", "file=comma,,in,,name,serial=$dollar$",
    "-cdrom", "\"$quoted\".iso",
    NULL
  };

  for (i = 0; actual_argv[i] != NULL; ++i) {
    if (expected_argv[i] == NULL ||
        strcmp (actual_argv[i], expected_argv[i])) {
      fprintf (stderr, "qemuopts: actual != expected argv at position %zu, %s != %s\n",
               i, actual_argv[i], expected_argv[i]);
      exit (EXIT_FAILURE);
    }
  }
  assert (expected_argv[i] == NULL);

  for (i = 0; actual_argv[i] != NULL; ++i)
    free (actual_argv[i]);
  free (actual_argv);

  qemuopts_free (qopts);

  /* Test qemuopts_to_config_channel. */
  qopts = qemuopts_create ();

  CHECK_ERROR (-1, "qemuopts_start_arg_list",
               qemuopts_start_arg_list (qopts, "-drive"));
  CHECK_ERROR (-1, "qemuopts_append_arg_list",
               qemuopts_append_arg_list (qopts, "file=/tmp/foo"));
  CHECK_ERROR (-1, "qemuopts_append_arg_list",
               qemuopts_append_arg_list (qopts, "id=id"));
  CHECK_ERROR (-1, "qemuopts_append_arg_list_format",
               qemuopts_append_arg_list_format (qopts, "if=%s", "ide"));
  CHECK_ERROR (-1, "qemuopts_append_arg_list_format",
               qemuopts_append_arg_list_format (qopts, "bool"));
  CHECK_ERROR (-1, "qemuopts_end_arg_list",
               qemuopts_end_arg_list (qopts));
  CHECK_ERROR (-1, "qemuopts_add_arg_list",
               qemuopts_add_arg_list (qopts, "-drive",
                                      "file=/tmp/bar", "serial=123",
                                      NULL));

  fp = open_memstream (&actual, &len);
  if (fp == NULL) {
    perror ("open_memstream");
    exit (EXIT_FAILURE);
  }
  CHECK_ERROR (-1, "qemuopts_to_config_channel",
               qemuopts_to_config_channel (qopts, fp));
  if (fclose (fp) == EOF) {
    perror ("fclose");
    exit (EXIT_FAILURE);
  }

  const char *expected2 =
    "# qemu config file\n"
    "\n"
    "[drive \"id\"]\n"
    "  file = \"/tmp/foo\"\n"
    "  if = \"ide\"\n"
    "  bool = \"on\"\n"
    "\n"
    "[drive]\n"
    "  file = \"/tmp/bar\"\n"
    "  serial = \"123\"\n"
    "\n";

  if (strcmp (actual, expected2) != 0) {
    fprintf (stderr, "qemuopts: Serialized qemu command line does not match expected\n");
    fprintf (stderr, "Actual:\n%s", actual);
    fprintf (stderr, "Expected:\n%s", expected2);
    exit (EXIT_FAILURE);
  }

  free (actual);

  qemuopts_free (qopts);

  exit (EXIT_SUCCESS);
}
