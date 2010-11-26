/* libguestfs - guestfish shell
 * Copyright (C) 2010 Red Hat Inc.
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

#ifndef FISH_CMDS_GPERF_H
#define FISH_CMDS_GPERF_H

/* There is one of these structures for each individual command that
 * guestfish can execute.
 */
struct command_entry {
  const char *name;             /* Short name. */
  const char *help;             /* Online help. */

  /* The run_* function. */
  int (*run) (const char *cmd, size_t argc, char *argv[]);
};

/* Command table used by the gperf-generated lookup function.
 * Multiple rows in this table can and do point to a single command
 * entry.  This is used to implement aliases.
 */
struct command_table {
  char *name;
  struct command_entry *entry;
};

const struct command_table *lookup_fish_command (register const char *str, register unsigned int len);

#endif /* FISH_CMDS_GPERF_H */
