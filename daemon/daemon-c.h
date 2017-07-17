/* guestfs-inspection
 * Copyright (C) 2017 Red Hat Inc.
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

/* This file is separate from <daemon.h> because we don't want to
 * include the OCaml headers (to get 'value') for the whole daemon.
 */

#ifndef GUESTFSD_DAEMON_C_H
#define GUESTFSD_DAEMON_C_H

#include "daemon.h"

#include <caml/mlvalues.h>

extern void guestfs_int_daemon_exn_to_reply_with_error (const char *func, value exn);
extern value guestfs_int_daemon_copy_mountable (const mountable_t *mountable);
extern char **guestfs_int_daemon_return_string_list (value retv);
extern char *guestfs_int_daemon_return_string_mountable (value retv);
extern char **guestfs_int_daemon_return_string_mountable_list (value retv);
extern char **guestfs_int_daemon_return_hashtable_string_string (value retv);
extern char **guestfs_int_daemon_return_hashtable_mountable_string (value retv);
extern char **guestfs_int_daemon_return_hashtable_string_mountable (value retv);

#endif /* GUESTFSD_DAEMON_C_H */
