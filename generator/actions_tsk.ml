(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Types

(* SleuthKit APIs. *)

let non_daemon_functions = [
  { defaults with
    name = "filesystem_walk"; added = (1, 33, 39);
    style = RStructList ("dirents", "tsk_dirent"), [String (Mountable, "device");], [];
    optional = Some "libtsk";
    progress = true; cancellable = true;
    shortdesc = "walk through the filesystem content";
    longdesc = "\
Walk through the internal structures of a disk partition
(eg. F</dev/sda1>) in order to return a list of all the files
and directories stored within.

It is not necessary to mount the disk partition to run this command.

All entries in the filesystem are returned. This function can list deleted
or unaccessible files. The entries are I<not> sorted.

The C<tsk_dirent> structure contains the following fields.

=over 4

=item C<tsk_inode>

Filesystem reference number of the node. It might be C<0>
if the node has been deleted.

=item C<tsk_type>

Basic file type information.
See below for a detailed list of values.

=item C<tsk_size>

File size in bytes. It might be C<-1>
if the node has been deleted.

=item C<tsk_name>

The file path relative to its directory.

=item C<tsk_flags>

Bitfield containing extra information regarding the entry.
It contains the logical OR of the following values:

=over 4

=item 0x0001

If set to C<1>, the file is allocated and visible within the filesystem.
Otherwise, the file has been deleted.
Under certain circumstances, the function C<download_inode>
can be used to recover deleted files.

=item 0x0002

Filesystem such as NTFS and Ext2 or greater, separate the file name
from the metadata structure.
The bit is set to C<1> when the file name is in an unallocated state
and the metadata structure is in an allocated one.
This generally implies the metadata has been reallocated to a new file.
Therefore, information such as file type, file size, timestamps,
number of links and symlink target might not correspond
with the ones of the original deleted entry.

=item 0x0004

The bit is set to C<1> when the file is compressed using filesystem
native compression support (NTFS). The API is not able to detect
application level compression.

=back

=item C<tsk_atime_sec>

=item C<tsk_atime_nsec>

=item C<tsk_mtime_sec>

=item C<tsk_mtime_nsec>

=item C<tsk_ctime_sec>

=item C<tsk_ctime_nsec>

=item C<tsk_crtime_sec>

=item C<tsk_crtime_nsec>

Respectively, access, modification, last status change and creation
time in Unix format in seconds and nanoseconds.

=item C<tsk_nlink>

Number of file names pointing to this entry.

=item C<tsk_link>

If the entry is a symbolic link, this field will contain the path
to the target file.

=back

The C<tsk_type> field will contain one of the following characters:

=over 4

=item 'b'

Block special

=item 'c'

Char special

=item 'd'

Directory

=item 'f'

FIFO (named pipe)

=item 'l'

Symbolic link

=item 'r'

Regular file

=item 's'

Socket

=item 'h'

Shadow inode (Solaris)

=item 'w'

Whiteout inode (BSD)

=item 'u'

Unknown file type

=back" };

  { defaults with
    name = "find_inode"; added = (1, 35, 6);
    style = RStructList ("dirents", "tsk_dirent"), [String (Mountable, "device"); Int64 "inode";], [];
    optional = Some "libtsk";
    progress = true; cancellable = true;
    shortdesc = "search the entries associated to the given inode";
    longdesc = "\
Searches all the entries associated with the given inode.

For each entry, a C<tsk_dirent> structure is returned.
See C<filesystem_walk> for more information about C<tsk_dirent> structures." };

]

let daemon_functions = [
  { defaults with
    name = "download_inode"; added = (1, 33, 14);
    style = RErr, [String (Mountable, "device"); Int64 "inode"; String (FileOut, "filename")], [];
    optional = Some "sleuthkit";
    progress = true; cancellable = true;
    shortdesc = "download a file to the local machine given its inode";
    longdesc = "\
Download a file given its inode from the disk partition
(eg. F</dev/sda1>) and save it as F<filename> on the local machine.

It is not required to mount the disk to run this command.

The command is capable of downloading deleted or inaccessible files." };

  { defaults with
    name = "internal_filesystem_walk"; added = (1, 33, 39);
    style = RErr, [String (Mountable, "device"); String (FileOut, "filename")], [];
    visibility = VInternal;
    optional = Some "libtsk";
    shortdesc = "walk through the filesystem content";
    longdesc = "Internal function for filesystem_walk." };

  { defaults with
    name = "download_blocks"; added = (1, 33, 45);
    style = RErr, [String (Mountable, "device"); Int64 "start"; Int64 "stop"; String (FileOut, "filename")], [OBool "unallocated"];
    optional = Some "sleuthkit";
    progress = true; cancellable = true;
    shortdesc = "download the given data units from the disk";
    longdesc = "\
Download the data units from F<start> address
to F<stop> from the disk partition (eg. F</dev/sda1>)
and save them as F<filename> on the local machine.

The use of this API on sparse disk image formats such as QCOW,
may result in large zero-filled files downloaded on the host.

The size of a data unit varies across filesystem implementations.
On NTFS filesystems data units are referred as clusters
while on ExtX ones they are referred as fragments.

If the optional C<unallocated> flag is true (default is false),
only the unallocated blocks will be extracted.
This is useful to detect hidden data or to retrieve deleted files
which data units have not been overwritten yet." };

  { defaults with
    name = "internal_find_inode"; added = (1, 35, 6);
    style = RErr, [String (Mountable, "device"); Int64 "inode"; String (FileOut, "filename");], [];
    visibility = VInternal;
    optional = Some "libtsk";
    shortdesc = "search the entries associated to the given inode";
    longdesc = "Internal function for find_inode." };

]
