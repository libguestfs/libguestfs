/* Non-blocking I/O for pipe or socket descriptors.
   Copyright (C) 2011-2023 Free Software Foundation, Inc.

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

#ifndef _NONBLOCKING_H
#define _NONBLOCKING_H

#include <stdbool.h>

/* Non-blocking I/O is an I/O mode by which read(), write() calls avoid
   blocking the current thread.  When non-blocking is enabled:
   - A read() call returns -1 with errno set to EAGAIN when no data or EOF
     information is immediately available.
   - A write() call returns -1 with errno set to EAGAIN when it cannot
     transport the requested amount of data (but at most one pipe buffer)
     without blocking.
   Non-blocking I/O is most useful for character devices, pipes, and sockets.
   Whether it also works on regular files and block devices is platform
   dependent.

   There are three modern alternatives to non-blocking I/O:
     - use select() or poll() followed by read() or write() if the descriptor
       is ready,
     - call read() or write() in separate threads,
     - use <aio.h> interfaces.  */


#ifdef __cplusplus
extern "C" {
#endif


/* Return 1 if I/O to the descriptor DESC is currently non-blocking, 0
   it is blocking, or -1 with errno set if fd is invalid or blocking
   status cannot be determined (such as with sockets on mingw).  */
extern int get_nonblocking_flag (int desc);

/* Specify the non-blocking flag for the descriptor DESC.
   Return 0 upon success, or -1 with errno set upon failure.
   The default depends on the presence of the O_NONBLOCK flag for files
   or pipes opened with open() or on the presence of the SOCK_NONBLOCK
   flag for sockets.  */
extern int set_nonblocking_flag (int desc, bool value);


#ifdef __cplusplus
}
#endif

#endif /* _NONBLOCKING_H */
