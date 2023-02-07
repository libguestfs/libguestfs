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

open Utils
open Types

(* "Core" APIs.  All the APIs in this file are deprecated. *)

let non_daemon_functions = [
  { defaults with
    name = "wait_ready"; added = (0, 0, 3);
    style = RErr, [], [];
    visibility = VStateTest;
    deprecated_by = Deprecated_no_replacement;
    blocking = false;
    shortdesc = "wait until the hypervisor launches (no op)";
    longdesc = "\
This function is a no op.

In versions of the API E<lt> 1.0.71 you had to call this function
just after calling C<guestfs_launch> to wait for the launch
to complete.  However this is no longer necessary because
C<guestfs_launch> now does the waiting.

If you see any calls to this function in code then you can just
remove them, unless you want to retain compatibility with older
versions of the API." };

  { defaults with
    name = "kill_subprocess"; added = (0, 0, 3);
    style = RErr, [], [];
    deprecated_by = Replaced_by "shutdown";
    shortdesc = "kill the hypervisor";
    longdesc = "\
This kills the hypervisor.

Do not call this.  See: C<guestfs_shutdown> instead." };

  { defaults with
    name = "add_cdrom"; added = (0, 0, 3);
    style = RErr, [String (PlainString, "filename")], [];
    deprecated_by = Replaced_by "add_drive_ro"; config_only = true;
    blocking = false;
    shortdesc = "add a CD-ROM disk image to examine";
    longdesc = "\
This function adds a virtual CD-ROM disk image to the guest.

The image is added as read-only drive, so this function is equivalent
of C<guestfs_add_drive_ro>." };

  { defaults with
    name = "add_drive_with_if"; added = (1, 0, 84);
    style = RErr, [String (PlainString, "filename"); String (PlainString, "iface")], [];
    deprecated_by = Replaced_by "add_drive"; config_only = true;
    blocking = false;
    shortdesc = "add a drive specifying the QEMU block emulation to use";
    longdesc = "\
This is the same as C<guestfs_add_drive> but it allows you
to specify the QEMU interface emulation to use at run time.
Both the direct and the libvirt backends ignore C<iface>." };

  { defaults with
    name = "add_drive_ro_with_if"; added = (1, 0, 84);
    style = RErr, [String (PlainString, "filename"); String (PlainString, "iface")], [];
    blocking = false;
    deprecated_by = Replaced_by "add_drive"; config_only = true;
    shortdesc = "add a drive read-only specifying the QEMU block emulation to use";
    longdesc = "\
This is the same as C<guestfs_add_drive_ro> but it allows you
to specify the QEMU interface emulation to use at run time.
Both the direct and the libvirt backends ignore C<iface>." };

  { defaults with
    name = "lstatlist"; added = (1, 0, 77);
    style = RStructList ("statbufs", "stat"), [String (Pathname, "path"); StringList (Filename, "names")], [];
    deprecated_by = Replaced_by "lstatnslist";
    shortdesc = "lstat on multiple files";
    longdesc = "\
This call allows you to perform the C<guestfs_lstat> operation
on multiple files, where all files are in the directory C<path>.
C<names> is the list of files from this directory.

On return you get a list of stat structs, with a one-to-one
correspondence to the C<names> list.  If any name did not exist
or could not be lstat'd, then the C<st_ino> field of that structure
is set to C<-1>.

This call is intended for programs that want to efficiently
list a directory contents without making many round-trips.
See also C<guestfs_lxattrlist> for a similarly efficient call
for getting extended attributes." };

  { defaults with
    name = "stat"; added = (1, 9, 2);
    style = RStruct ("statbuf", "stat"), [String (Pathname, "path")], [];
    deprecated_by = Replaced_by "statns";
    tests = [
      InitISOFS, Always, TestResult (
        [["stat"; "/empty"]], "ret->size == 0"), []
    ];
    shortdesc = "get file information";
    longdesc = "\
Returns file information for the given C<path>.

This is the same as the L<stat(2)> system call." };

  { defaults with
    name = "lstat"; added = (1, 9, 2);
    style = RStruct ("statbuf", "stat"), [String (Pathname, "path")], [];
    deprecated_by = Replaced_by "lstatns";
    tests = [
      InitISOFS, Always, TestResult (
        [["lstat"; "/empty"]], "ret->size == 0"), []
    ];
    shortdesc = "get file information for a symbolic link";
    longdesc = "\
Returns file information for the given C<path>.

This is the same as C<guestfs_stat> except that if C<path>
is a symbolic link, then the link is stat-ed, not the file it
refers to.

This is the same as the L<lstat(2)> system call." };

  { defaults with
    name = "remove_drive"; added = (1, 19, 49);
    style = RErr, [String (PlainString, "label")], [];
    deprecated_by = Deprecated_no_replacement;
    blocking = false;
    shortdesc = "remove a disk image";
    longdesc = "\
This call does nothing and returns an error." };

]

let daemon_functions = [
  { defaults with
    name = "sfdisk"; added = (0, 0, 8);
    style = RErr, [String (Device, "device");
                   Int "cyls"; Int "heads"; Int "sectors";
                   StringList (PlainString, "lines")], [];
    deprecated_by = Replaced_by "part_add";
    shortdesc = "create partitions on a block device";
    longdesc = "\
This is a direct interface to the L<sfdisk(8)> program for creating
partitions on block devices.

C<device> should be a block device, for example F</dev/sda>.

C<cyls>, C<heads> and C<sectors> are the number of cylinders, heads
and sectors on the device, which are passed directly to L<sfdisk(8)>
as the I<-C>, I<-H> and I<-S> parameters.  If you pass C<0> for any
of these, then the corresponding parameter is omitted.  Usually for
‘large’ disks, you can just pass C<0> for these, but for small
(floppy-sized) disks, L<sfdisk(8)> (or rather, the kernel) cannot work
out the right geometry and you will need to tell it.

C<lines> is a list of lines that we feed to L<sfdisk(8)>.  For more
information refer to the L<sfdisk(8)> manpage.

To create a single partition occupying the whole disk, you would
pass C<lines> as a single element list, when the single element being
the string C<,> (comma).

See also: C<guestfs_sfdisk_l>, C<guestfs_sfdisk_N>,
C<guestfs_part_init>" };

  { defaults with
    name = "blockdev_setbsz"; added = (1, 9, 3);
    style = RErr, [String (Device, "device"); Int "blocksize"], [];
    deprecated_by = Deprecated_no_replacement;
    shortdesc = "set blocksize of block device";
    longdesc = "\
This call does nothing and has never done anything
because of a bug in blockdev.  B<Do not use it.>

If you need to set the filesystem block size, use the
C<blocksize> option of C<guestfs_mkfs>." };

  { defaults with
    name = "tgz_in"; added = (1, 0, 3);
    style = RErr, [String (FileIn, "tarball"); String (Pathname, "directory")], [];
    deprecated_by = Replaced_by "tar_in";
    cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/tgz_in"];
         ["tgz_in"; "$srcdir/../test-data/files/helloworld.tar.gz"; "/tgz_in"];
         ["cat"; "/tgz_in/hello"]], "hello\n"), []
    ];
    shortdesc = "unpack compressed tarball to directory";
    longdesc = "\
This command uploads and unpacks local file C<tarball> (a
I<gzip compressed> tar file) into F<directory>." };

  { defaults with
    name = "tgz_out"; added = (1, 0, 3);
    style = RErr, [String (Pathname, "directory"); String (FileOut, "tarball")], [];
    deprecated_by = Replaced_by "tar_out";
    cancellable = true;
    shortdesc = "pack directory into compressed tarball";
    longdesc = "\
This command packs the contents of F<directory> and downloads
it to local file C<tarball>." };

  { defaults with
    name = "set_e2label"; added = (1, 0, 15);
    style = RErr, [String (Device, "device"); String (PlainString, "label")], [];
    deprecated_by = Replaced_by "set_label";
    tests = [
      InitBasicFS, Always, TestResultString (
        [["set_e2label"; "/dev/sda1"; "testlabel"];
         ["get_e2label"; "/dev/sda1"]], "testlabel"), []
    ];
    shortdesc = "set the ext2/3/4 filesystem label";
    longdesc = "\
This sets the ext2/3/4 filesystem label of the filesystem on
C<device> to C<label>.  Filesystem labels are limited to
16 characters.

You can use either C<guestfs_tune2fs_l> or C<guestfs_get_e2label>
to return the existing label on a filesystem." };

  { defaults with
    name = "get_e2label"; added = (1, 0, 15);
    style = RString (RPlainString, "label"), [String (Device, "device")], [];
    deprecated_by = Replaced_by "vfs_label";
    shortdesc = "get the ext2/3/4 filesystem label";
    longdesc = "\
This returns the ext2/3/4 filesystem label of the filesystem on
C<device>." };

  { defaults with
    name = "set_e2uuid"; added = (1, 0, 15);
    style = RErr, [String (Device, "device"); String (PlainString, "uuid")], [];
    deprecated_by = Replaced_by "set_uuid";
    tests = [
        InitBasicFS, Always, TestResultString (
          [["set_e2uuid"; "/dev/sda1"; stable_uuid];
           ["get_e2uuid"; "/dev/sda1"]], stable_uuid), [];
        InitBasicFS, Always, TestResultString (
          [["set_e2uuid"; "/dev/sda1"; "clear"];
           ["get_e2uuid"; "/dev/sda1"]], ""), [];
        (* We can't predict what UUIDs will be, so just check
           the commands run. *)
        InitBasicFS, Always, TestRun (
          [["set_e2uuid"; "/dev/sda1"; "random"]]), [];
        InitBasicFS, Always, TestRun (
          [["set_e2uuid"; "/dev/sda1"; "time"]]), []
      ];
    shortdesc = "set the ext2/3/4 filesystem UUID";
    longdesc = "\
This sets the ext2/3/4 filesystem UUID of the filesystem on
C<device> to C<uuid>.  The format of the UUID and alternatives
such as C<clear>, C<random> and C<time> are described in the
L<tune2fs(8)> manpage.

You can use C<guestfs_vfs_uuid> to return the existing UUID
of a filesystem." };

  { defaults with
    name = "get_e2uuid"; added = (1, 0, 15);
    style = RString (RPlainString, "uuid"), [String (Device, "device")], [];
    deprecated_by = Replaced_by "vfs_uuid";
    tests = [
      (* We can't predict what UUID will be, so just check
         the command run; regression test for RHBZ#597112. *)
      InitNone, Always, TestRun (
        [["mke2journal"; "1024"; "/dev/sdc"];
         ["get_e2uuid"; "/dev/sdc"]]), []
    ];
    shortdesc = "get the ext2/3/4 filesystem UUID";
    longdesc = "\
This returns the ext2/3/4 filesystem UUID of the filesystem on
C<device>." };

  { defaults with
    name = "sfdisk_N"; added = (1, 0, 26);
    style = RErr, [String (Device, "device"); Int "partnum";
                   Int "cyls"; Int "heads"; Int "sectors";
                   String (PlainString, "line")], [];
    deprecated_by = Replaced_by "part_add";
    shortdesc = "modify a single partition on a block device";
    longdesc = "\
This runs L<sfdisk(8)> option to modify just the single
partition C<n> (note: C<n> counts from 1).

For other parameters, see C<guestfs_sfdisk>.  You should usually
pass C<0> for the cyls/heads/sectors parameters.

See also: C<guestfs_part_add>" };

  { defaults with
    name = "sfdisk_l"; added = (1, 0, 26);
    style = RString (RDevice, "partitions"), [String (Device, "device")], [];
    deprecated_by = Replaced_by "part_list";
    shortdesc = "display the partition table";
    longdesc = "\
This displays the partition table on C<device>, in the
human-readable output of the L<sfdisk(8)> command.  It is
not intended to be parsed.

See also: C<guestfs_part_list>" };

  { defaults with
    name = "e2fsck_f"; added = (1, 0, 29);
    style = RErr, [String (Device, "device")], [];
    deprecated_by = Replaced_by "e2fsck";
    shortdesc = "check an ext2/ext3 filesystem";
    longdesc = "\
This runs C<e2fsck -p -f device>, ie. runs the ext2/ext3
filesystem checker on C<device>, noninteractively (I<-p>),
even if the filesystem appears to be clean (I<-f>)." };

  { defaults with
    name = "mkswap_L"; added = (1, 0, 55);
    style = RErr, [String (PlainString, "label"); String (Device, "device")], [];
    deprecated_by = Replaced_by "mkswap";
    tests = [
      InitEmpty, Always, TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkswap_L"; "hello"; "/dev/sda1"]]), []
    ];
    shortdesc = "create a swap partition with a label";
    longdesc = "\
Create a swap partition on C<device> with label C<label>.

Note that you cannot attach a swap label to a block device
(eg. F</dev/sda>), just to a partition.  This appears to be
a limitation of the kernel or swap tools." };

  { defaults with
    name = "mkswap_U"; added = (1, 0, 55);
    style = RErr, [String (PlainString, "uuid"); String (Device, "device")], [];
    deprecated_by = Replaced_by "mkswap";
    optional = Some "linuxfsuuid";
    tests = [
        InitEmpty, Always, TestRun (
          [["part_disk"; "/dev/sda"; "mbr"];
           ["mkswap_U"; stable_uuid; "/dev/sda1"]]), []
      ];
    shortdesc = "create a swap partition with an explicit UUID";
    longdesc = "\
Create a swap partition on C<device> with UUID C<uuid>." };

  { defaults with
    name = "sfdiskM"; added = (1, 0, 55);
    style = RErr, [String (Device, "device"); StringList (PlainString, "lines")], [];
    deprecated_by = Replaced_by "part_add";
    shortdesc = "create partitions on a block device";
    longdesc = "\
This is a simplified interface to the C<guestfs_sfdisk>
command, where partition sizes are specified in megabytes
only (rounded to the nearest cylinder) and you don't need
to specify the cyls, heads and sectors parameters which
were rarely if ever used anyway.

See also: C<guestfs_sfdisk>, the L<sfdisk(8)> manpage
and C<guestfs_part_disk>" };

  { defaults with
    name = "zfile"; added = (1, 0, 59);
    style = RString (RPlainString, "description"), [String (PlainString, "meth"); String (Pathname, "path")], [];
    deprecated_by = Replaced_by "file";
    shortdesc = "determine file type inside a compressed file";
    longdesc = "\
This command runs L<file(1)> after first decompressing C<path>
using C<meth>.

C<meth> must be one of C<gzip>, C<compress> or C<bzip2>.

Since 1.0.63, use C<guestfs_file> instead which can now
process compressed files." };

  { defaults with
    name = "egrep"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["egrep"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external L<egrep(1)> program and returns the
matching lines." };

  { defaults with
    name = "fgrep"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "pattern"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["fgrep"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external L<fgrep(1)> program and returns the
matching lines." };

  { defaults with
    name = "grepi"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["grepi"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<grep -i> program and returns the
matching lines." };

  { defaults with
    name = "egrepi"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["egrepi"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<egrep -i> program and returns the
matching lines." };

  { defaults with
    name = "fgrepi"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "pattern"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["fgrepi"; "abc"; "/test-grep.txt"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<fgrep -i> program and returns the
matching lines." };

  { defaults with
    name = "zgrep"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zgrep"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external L<zgrep(1)> program and returns the
matching lines." };

  { defaults with
    name = "zegrep"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zegrep"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zegrep> program and returns the
matching lines." };

  { defaults with
    name = "zfgrep"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "pattern"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zfgrep"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 2, \"abc\", \"abc123\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zfgrep> program and returns the
matching lines." };

  { defaults with
    name = "zgrepi"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];

    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zgrepi"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zgrep -i> program and returns the
matching lines." };

  { defaults with
    name = "zegrepi"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "regex"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zegrepi"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zegrep -i> program and returns the
matching lines." };

  { defaults with
    name = "zfgrepi"; added = (1, 0, 66);
    style = RStringList (RPlainString, "lines"), [String (PlainString, "pattern"); String (Pathname, "path")], [];
    protocol_limit_warning = true;
    deprecated_by = Replaced_by "grep";
    tests = [
      InitISOFS, Always, TestResult (
        [["zfgrepi"; "abc"; "/test-grep.txt.gz"]],
        "is_string_list (ret, 3, \"abc\", \"abc123\", \"ABC\")"), []
    ];
    shortdesc = "return lines matching a pattern";
    longdesc = "\
This calls the external C<zfgrep -i> program and returns the
matching lines." };

  { defaults with
    name = "fallocate"; added = (1, 0, 66);
    style = RErr, [String (Pathname, "path"); Int "len"], [];
    deprecated_by = Replaced_by "fallocate64";
    tests = [
      InitScratchFS, Always, TestResult (
        [["fallocate"; "/fallocate"; "1000000"];
         ["stat"; "/fallocate"]], "ret->size == 1000000"), []
    ];
    shortdesc = "preallocate a file in the guest filesystem";
    longdesc = "\
This command preallocates a file (containing zero bytes) named
C<path> of size C<len> bytes.  If the file exists already, it
is overwritten.

Do not confuse this with the guestfish-specific
C<alloc> command which allocates a file in the host and
attaches it as a device." };

  { defaults with
    name = "setcon"; added = (1, 0, 67);
    style = RErr, [String (PlainString, "context")], [];
    optional = Some "selinux";
    deprecated_by = Replaced_by "selinux_relabel";
    shortdesc = "set SELinux security context";
    longdesc = "\
This sets the SELinux security context of the daemon
to the string C<context>.

See the documentation about SELINUX in L<guestfs(3)>." };

  { defaults with
    name = "getcon"; added = (1, 0, 67);
    style = RString (RPlainString, "context"), [], [];
    optional = Some "selinux";
    deprecated_by = Replaced_by "selinux_relabel";
    shortdesc = "get SELinux security context";
    longdesc = "\
This gets the SELinux security context of the daemon.

See the documentation about SELINUX in L<guestfs(3)>,
and C<guestfs_setcon>" };

  { defaults with
    name = "mkfs_b"; added = (1, 0, 68);
    style = RErr, [String (PlainString, "fstype"); Int "blocksize"; String (Device, "device")], [];
    deprecated_by = Replaced_by "mkfs";
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs_b"; "ext2"; "4096"; "/dev/sda1"];
         ["mount"; "/dev/sda1"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), [];
      InitEmpty, Always, TestRun (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["mkfs_b"; "vfat"; "32768"; "/dev/sda1"]]), [];
      InitEmpty, Always, TestLastFail (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["mkfs_b"; "vfat"; "32769"; "/dev/sda1"]]), [];
      InitEmpty, Always, TestLastFail (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["mkfs_b"; "vfat"; "33280"; "/dev/sda1"]]), [];
      InitEmpty, IfAvailable "ntfsprogs", TestRun (
        [["part_disk"; "/dev/sda"; "mbr"];
         ["mkfs_b"; "ntfs"; "32768"; "/dev/sda1"]]), []
    ];
    shortdesc = "make a filesystem with block size";
    longdesc = "\
This call is similar to C<guestfs_mkfs>, but it allows you to
control the block size of the resulting filesystem.  Supported
block sizes depend on the filesystem type, but typically they
are C<1024>, C<2048> or C<4096> only.

For VFAT and NTFS the C<blocksize> parameter is treated as
the requested cluster size." };

  { defaults with
    name = "mke2journal"; added = (1, 0, 68);
    style = RErr, [Int "blocksize"; String (Device, "device")], [];
    deprecated_by = Replaced_by "mke2fs";
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
         ["mke2journal"; "4096"; "/dev/sda1"];
         ["mke2fs_J"; "ext2"; "4096"; "/dev/sda2"; "/dev/sda1"];
         ["mount"; "/dev/sda2"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), []
    ];
    shortdesc = "make ext2/3/4 external journal";
    longdesc = "\
This creates an ext2 external journal on C<device>.  It is equivalent
to the command:

 mke2fs -O journal_dev -b blocksize device" };

  { defaults with
    name = "mke2journal_L"; added = (1, 0, 68);
    style = RErr, [Int "blocksize"; String (PlainString, "label"); String (Device, "device")], [];
    deprecated_by = Replaced_by "mke2fs";
    tests = [
      InitEmpty, Always, TestResultString (
        [["part_init"; "/dev/sda"; "mbr"];
         ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
         ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
         ["mke2journal_L"; "4096"; "JOURNAL"; "/dev/sda1"];
         ["mke2fs_JL"; "ext2"; "4096"; "/dev/sda2"; "JOURNAL"];
         ["mount"; "/dev/sda2"; "/"];
         ["write"; "/new"; "new file contents"];
         ["cat"; "/new"]], "new file contents"), []
    ];
    shortdesc = "make ext2/3/4 external journal with label";
    longdesc = "\
This creates an ext2 external journal on C<device> with label C<label>." };

  { defaults with
    name = "mke2journal_U"; added = (1, 0, 68);
    style = RErr, [Int "blocksize"; String (PlainString, "uuid"); String (Device, "device")], [];
    deprecated_by = Replaced_by "mke2fs";
    optional = Some "linuxfsuuid";
    tests = [
        InitEmpty, Always, TestResultString (
          [["part_init"; "/dev/sda"; "mbr"];
           ["part_add"; "/dev/sda"; "p"; "64"; "204799"];
           ["part_add"; "/dev/sda"; "p"; "204800"; "-64"];
           ["mke2journal_U"; "4096"; stable_uuid; "/dev/sda1"];
           ["mke2fs_JU"; "ext2"; "4096"; "/dev/sda2"; stable_uuid];
           ["mount"; "/dev/sda2"; "/"];
           ["write"; "/new"; "new file contents"];
           ["cat"; "/new"]], "new file contents"), []
      ];
    shortdesc = "make ext2/3/4 external journal with UUID";
    longdesc = "\
This creates an ext2 external journal on C<device> with UUID C<uuid>." };

  { defaults with
    name = "mke2fs_J"; added = (1, 0, 68);
    style = RErr, [String (PlainString, "fstype"); Int "blocksize"; String (Device, "device"); String (Device, "journal")], [];
    deprecated_by = Replaced_by "mke2fs";
    shortdesc = "make ext2/3/4 filesystem with external journal";
    longdesc = "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on C<journal>.  It is equivalent
to the command:

 mke2fs -t fstype -b blocksize -J device=<journal> <device>

See also C<guestfs_mke2journal>." };

  { defaults with
    name = "mke2fs_JL"; added = (1, 0, 68);
    style = RErr, [String (PlainString, "fstype"); Int "blocksize"; String (Device, "device"); String (PlainString, "label")], [];
    deprecated_by = Replaced_by "mke2fs";
    shortdesc = "make ext2/3/4 filesystem with external journal";
    longdesc = "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal labeled C<label>.

See also C<guestfs_mke2journal_L>." };

  { defaults with
    name = "mke2fs_JU"; added = (1, 0, 68);
    style = RErr, [String (PlainString, "fstype"); Int "blocksize"; String (Device, "device"); String (PlainString, "uuid")], [];
    deprecated_by = Replaced_by "mke2fs";
    optional = Some "linuxfsuuid";
    shortdesc = "make ext2/3/4 filesystem with external journal";
    longdesc = "\
This creates an ext2/3/4 filesystem on C<device> with
an external journal on the journal with UUID C<uuid>.

See also C<guestfs_mke2journal_U>." };

  { defaults with
    name = "dd"; added = (1, 0, 80);
    style = RErr, [String (Dev_or_Path, "src"); String (Dev_or_Path, "dest")], [];
    deprecated_by = Replaced_by "copy_device_to_device";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/dd"];
         ["write"; "/dd/src"; "hello, world"];
         ["dd"; "/dd/src"; "/dd/dest"];
         ["read_file"; "/dd/dest"]],
        "compare_buffers (ret, size, \"hello, world\", 12) == 0"), []
    ];
    shortdesc = "copy from source to destination using dd";
    longdesc = "\
This command copies from one source device or file C<src>
to another destination device or file C<dest>.  Normally you
would use this to copy to or from a device or partition, for
example to duplicate a filesystem.

If the destination is a device, it must be as large or larger
than the source file or device, otherwise the copy will fail.
This command cannot do partial copies
(see C<guestfs_copy_device_to_device>)." };

  { defaults with
    name = "txz_in"; added = (1, 3, 2);
    style = RErr, [String (FileIn, "tarball"); String (Pathname, "directory")], [];
    deprecated_by = Replaced_by "tar_in";
    optional = Some "xz"; cancellable = true;
    tests = [
      InitScratchFS, Always, TestResultString (
        [["mkdir"; "/txz_in"];
         ["txz_in"; "$srcdir/../test-data/files/helloworld.tar.xz"; "/txz_in"];
         ["cat"; "/txz_in/hello"]], "hello\n"), []
    ];
    shortdesc = "unpack compressed tarball to directory";
    longdesc = "\
This command uploads and unpacks local file C<tarball> (an
I<xz compressed> tar file) into F<directory>." };

  { defaults with
    name = "txz_out"; added = (1, 3, 2);
    style = RErr, [String (Pathname, "directory"); String (FileOut, "tarball")], [];
    deprecated_by = Replaced_by "tar_out";
    optional = Some "xz"; cancellable = true;
    shortdesc = "pack directory into compressed tarball";
    longdesc = "\
This command packs the contents of F<directory> and downloads
it to local file C<tarball> (as an xz compressed tar archive)." };

  { defaults with
    name = "llz"; added = (1, 17, 6);
    style = RString (RPlainString, "listing"), [String (Pathname, "directory")], [];
    deprecated_by = Replaced_by "lgetxattrs";
    shortdesc = "list the files in a directory (long format with SELinux contexts)";
    longdesc = "\
List the files in F<directory> in the format of C<ls -laZ>.

This command is mostly useful for interactive sessions.  It
is I<not> intended that you try to parse the output string." };

  { defaults with
    name = "write_file"; added = (0, 0, 8);
    style = RErr, [String (Pathname, "path"); String (PlainString, "content"); Int "size"], [];
    protocol_limit_warning = true; deprecated_by = Replaced_by "write";
    (* Regression test for RHBZ#597135. *)
    tests = [
      InitScratchFS, Always, TestLastFail
        [["write_file"; "/write_file"; "abc"; "10000"]], []
    ];
    shortdesc = "create a file";
    longdesc = "\
This call creates a file called C<path>.  The contents of the
file is the string C<content> (which can contain any 8 bit data),
with length C<size>.

As a special case, if C<size> is C<0>
then the length is calculated using C<strlen> (so in this case
the content cannot contain embedded ASCII NULs).

I<NB.> Owing to a bug, writing content containing ASCII NUL
characters does I<not> work, even if the length is specified." };

  { defaults with
    name = "copy_size"; added = (1, 0, 87);
    style = RErr, [String (Dev_or_Path, "src"); String (Dev_or_Path, "dest"); Int64 "size"], [];
    progress = true; deprecated_by = Replaced_by "copy_device_to_device";
    tests = [
      InitScratchFS, Always, TestResult (
        [["mkdir"; "/copy_size"];
         ["write"; "/copy_size/src"; "hello, world"];
         ["copy_size"; "/copy_size/src"; "/copy_size/dest"; "5"];
         ["read_file"; "/copy_size/dest"]],
        "compare_buffers (ret, size, \"hello\", 5) == 0"), []
    ];
    shortdesc = "copy size bytes from source to destination using dd";
    longdesc = "\
This command copies exactly C<size> bytes from one source device
or file C<src> to another destination device or file C<dest>.

Note this will fail if the source is too short or if the destination
is not large enough." };

  { defaults with
    name = "ntfsresize_size"; added = (1, 3, 14);
    style = RErr, [String (Device, "device"); Int64 "size"], [];
    optional = Some "ntfsprogs"; deprecated_by = Replaced_by "ntfsresize";
    shortdesc = "resize an NTFS filesystem (with size)";
    longdesc = "\
This command is the same as C<guestfs_ntfsresize> except that it
allows you to specify the new size (in bytes) explicitly." };

  { defaults with
    name = "vgscan"; added = (1, 3, 2);
    style = RErr, [], [];
    deprecated_by = Replaced_by "lvm_scan";
    tests = [
      InitEmpty, Always, TestRun (
        [["vgscan"]]), []
    ];
    shortdesc = "rescan for LVM physical volumes, volume groups and logical volumes";
    longdesc = "\
This rescans all block devices and rebuilds the list of LVM
physical volumes, volume groups and logical volumes." };

  { defaults with
    name = "luks_open"; added = (1, 5, 1);
    style = RErr, [String (Device, "device"); String (Key, "key"); String (PlainString, "mapname")], [];
    impl = OCaml "Cryptsetup.luks_open";
    optional = Some "luks";
    deprecated_by = Replaced_by "cryptsetup_open";
    shortdesc = "open a LUKS-encrypted block device";
    longdesc = "\
This command opens a block device which has been encrypted
according to the Linux Unified Key Setup (LUKS) standard.

C<device> is the encrypted block device or partition.

The caller must supply one of the keys associated with the
LUKS block device, in the C<key> parameter.

This creates a new block device called F</dev/mapper/mapname>.
Reads and writes to this block device are decrypted from and
encrypted to the underlying C<device> respectively.

If this block device contains LVM volume groups, then
calling C<guestfs_lvm_scan> with the C<activate>
parameter C<true> will make them visible.

Use C<guestfs_list_dm_devices> to list all device mapper
devices." };

  { defaults with
    name = "luks_open_ro"; added = (1, 5, 1);
    style = RErr, [String (Device, "device"); String (Key, "key"); String (PlainString, "mapname")], [];
    impl = OCaml "Cryptsetup.luks_open_ro";
    optional = Some "luks";
    deprecated_by = Replaced_by "cryptsetup_open";
    shortdesc = "open a LUKS-encrypted block device read-only";
    longdesc = "\
This is the same as C<guestfs_luks_open> except that a read-only
mapping is created." };

  { defaults with
    name = "luks_close"; added = (1, 5, 1);
    style = RErr, [String (Device, "device")], [];
    impl = OCaml "Cryptsetup.luks_close";
    optional = Some "luks";
    deprecated_by = Replaced_by "cryptsetup_close";
    shortdesc = "close a LUKS device";
    longdesc = "\
This closes a LUKS device that was created earlier by
C<guestfs_luks_open> or C<guestfs_luks_open_ro>.  The
C<device> parameter must be the name of the LUKS mapping
device (ie. F</dev/mapper/mapname>) and I<not> the name
of the underlying block device." };

  { defaults with
    name = "list_9p"; added = (1, 11, 12);
    style = RStringList (RPlainString, "mounttags"), [], [];
    shortdesc = "list 9p filesystems";
    deprecated_by = Deprecated_no_replacement;
    longdesc = "\
This call does nothing and returns an error." };

  { defaults with
    name = "mount_9p"; added = (1, 11, 12);
    style = RErr, [String (PlainString, "mounttag"); String (PlainString, "mountpoint")], [OString "options"];
    camel_name = "Mount9P";
    deprecated_by = Deprecated_no_replacement;
    shortdesc = "mount 9p filesystem";
    longdesc = "\
This call does nothing and returns an error." };

]
