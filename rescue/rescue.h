/* virt-rescue
 * Copyright (C) 2010-2023 Red Hat Inc.
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

#ifndef RESCUE_H
#define RESCUE_H

#include <stdbool.h>

#include "guestfs.h"

#include "options.h"

extern guestfs_h *g;
extern int read_only;
extern int live;
extern int verbose;
extern int keys_from_stdin;
extern int echo_keys;
extern const char *libvirt_uri;
extern int inspector;
extern int in_guestfish;
extern int in_virt_rescue;
extern int escape_key;

/* escape.c */
struct escape_state {
  bool in_escape;
};
extern void init_escape_state (struct escape_state *state);
extern bool process_escapes (struct escape_state *state, char *buf, size_t *len);
extern int parse_escape_key (const char *);
extern void print_escape_key_help (void);

/* suggest.c */
extern void do_suggestion (struct drv *drvs);

#endif /* RESCUE_H */
