/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2015 Red Hat Inc.
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

#ifndef GUESTFSD_COMMAND_H
#define GUESTFSD_COMMAND_H

#define command(out,err,name,...) commandf((out),(err),0,(name),__VA_ARGS__)
#define commandr(out,err,name,...) commandrf((out),(err),0,(name),__VA_ARGS__)
#define commandv(out,err,argv) commandvf((out),(err),0,(argv))
#define commandrv(out,err,argv) commandrvf((out),(err),0,(argv))

#define COMMAND_FLAG_FD_MASK                   0x0000ffff
#define COMMAND_FLAG_FOLD_STDOUT_ON_STDERR     0x00010000
#define COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN 0x00020000
#define COMMAND_FLAG_DO_CHROOT                 0x00040000

extern int commandf (char **stdoutput, char **stderror, unsigned flags,
                     const char *name, ...) __attribute__((sentinel));
extern int commandrf (char **stdoutput, char **stderror, unsigned flags,
                      const char *name, ...) __attribute__((sentinel));
extern int commandvf (char **stdoutput, char **stderror, unsigned flags,
                      char const *const *argv);
extern int commandrvf (char **stdoutput, char **stderror, unsigned flags,
                       char const* const *argv);

#endif /* GUESTFSD_COMMAND_H */
