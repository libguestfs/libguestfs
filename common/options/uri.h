/* libguestfs - mini library for parsing -a URI parameters
 * Copyright (C) 2013 Red Hat Inc.
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

#ifndef FISH_URI_H
#define FISH_URI_H

struct uri {
  char *path;                   /* disk path */
  char *protocol;               /* protocol (eg. "file", "nbd") */
  char **server;                /* server(s) - can be NULL */
  char *username;               /* username - can be NULL */
  char *password;               /* password - can be NULL */
};

/* Parse the '-a' option parameter 'arg', and place the result in
 * '*uri_ret'.
 *
 * If it doesn't look like a URI then uri_ret->path will be the same
 * as 'arg' (copied) and uri_ret->protocol will be "file".
 *
 * If it looks like a URI and can be parsed, then the other fields will
 * be filled in as appropriate.
 *
 * The caller should free the fields from the struct after use.
 *
 * Returns 0 if parsing went OK, or -1 if there was an error.
 */
extern int parse_uri (const char *arg, struct uri *uri_ret);

#endif /* FISH_URI_H */
