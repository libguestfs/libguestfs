/* cloexec.c - set or clear the close-on-exec descriptor flag

   Copyright (C) 2004, 2009-2023 Free Software Foundation, Inc.

   (NB: I modified the original GPL boilerplate here to LGPLv2+.  This
   is because of the weird way that gnulib uses licenses, where the
   real license is covered in the modules/X file.  The real license
   for this file is LGPLv2+, not GPL.  - RWMJ)

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <stdbool.h>

/* Set the 'FD_CLOEXEC' flag of DESC if VALUE is true,
   or clear the flag if VALUE is false.
   Return 0 on success, or -1 on error with 'errno' set.

   Note that on MingW, this function does NOT protect DESC from being
   inherited into spawned children.  Instead, either use dup_cloexec
   followed by closing the original DESC, or use interfaces such as
   open or pipe2 that accept flags like O_CLOEXEC to create DESC
   non-inheritable in the first place.  */

int set_cloexec_flag (int desc, bool value);

/* Duplicates a file handle FD, while marking the copy to be closed
   prior to exec or spawn.  Returns -1 and sets errno if FD could not
   be duplicated.  */

int dup_cloexec (int fd);
