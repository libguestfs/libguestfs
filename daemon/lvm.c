/* libguestfs - the guestfsd daemon
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
#include <ctype.h>

#include "daemon.h"
#include "actions.h"

/* LVM actions.  Keep an eye on liblvm, although at the time
 * of writing it hasn't progressed very far.
 */

guestfs_lvm_int_pv_list *
do_pvs_full (void)
{
  return parse_command_line_pvs ();
}

guestfs_lvm_int_vg_list *
do_vgs_full (void)
{
  return parse_command_line_vgs ();
}

guestfs_lvm_int_lv_list *
do_lvs_full (void)
{
  return parse_command_line_lvs ();
}
