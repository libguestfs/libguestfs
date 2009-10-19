#!/usr/bin/perl -w
# virt-edit
# Copyright (C) 2009 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use warnings;
use strict;

use Sys::Guestfs;
use Sys::Guestfs::Lib qw(open_guest get_partitions resolve_windows_path
  inspect_all_partitions inspect_partition
  inspect_operating_systems mount_operating_system);
use Pod::Usage;
use Getopt::Long;
use File::Temp qw/tempfile/;
use Locale::TextDomain 'libguestfs';

=encoding utf8

=head1 NAME

virt-edit - Edit a file in a virtual machine

=head1 SYNOPSIS

 virt-edit [--options] domname file

 virt-edit [--options] disk.img [disk.img ...] file

=head1 DESCRIPTION

C<virt-edit> is a command line tool to edit C<file> where C<file>
exists in the named virtual machine (or disk image).

B<Note> you must I<not> use virt-edit on live virtual machines.  If
you do this, you risk disk corruption in the VM.

If you want to just view a file, use L<virt-cat(1)>.  For more complex
cases you should look at the L<guestfish(1)> tool.

=head1 EXAMPLES

 virt-edit mydomain /boot/grub/grub.conf

 virt-edit mydomain /etc/passwd

=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $version;

=item B<--version>

Display version number and exit.

=cut

my $uri;

=item B<--connect URI> | B<-c URI>

If using libvirt, connect to the given I<URI>.  If omitted, then we
connect to the default libvirt hypervisor.

If you specify guest block devices directly, then libvirt is not used
at all.

=back

=cut

GetOptions ("help|?" => \$help,
            "version" => \$version,
            "connect|c=s" => \$uri,
    ) or pod2usage (2);
pod2usage (1) if $help;
if ($version) {
    my $g = Sys::Guestfs->new ();
    my %h = $g->version ();
    print "$h{major}.$h{minor}.$h{release}$h{extra}\n";
    exit
}

pod2usage (__"virt-edit: no image, VM names or filenames to edit given")
    if @ARGV <= 1;

my $filename = pop @ARGV;

my $g;
if ($uri) {
    $g = open_guest (\@ARGV, address => $uri, rw => 1);
} else {
    $g = open_guest (\@ARGV, rw => 1);
}

$g->launch ();

# List of possible filesystems.
my @partitions = get_partitions ($g);

# Now query each one to build up a picture of what's in it.
my %fses =
    inspect_all_partitions ($g, \@partitions,
      use_windows_registry => 0);

my $oses = inspect_operating_systems ($g, \%fses);

my @roots = keys %$oses;
die __"no root device found in this operating system image" if @roots == 0;
die __"multiboot operating systems are not supported by virt-edit" if @roots > 1;
my $root_dev = $roots[0];

my $os = $oses->{$root_dev};
mount_operating_system ($g, $os, 0);

my ($fh, $tempname) = tempfile ();

# Allow this to fail in case eg. the file does not exist.
$g->download($filename, $tempname);

my $oldctime = (stat ($tempname))[10];

my $editor = $ENV{EDITOR};
$editor ||= "vi";
system ("$editor $tempname") == 0
    or die "edit failed: $editor: $?";

my $newctime = (stat ($tempname))[10];

if ($oldctime != $newctime) {
    $g->upload ($tempname, $filename)
} else {
    print __"File not changed.\n";
}

$g->sync ();
$g->umount_all ();

undef $g;

exit 0;

=head1 ENVIRONMENT VARIABLES

=over 4

=item C<EDITOR>

If set, this string is used as the editor.  It may contain arguments,
eg. C<"emacs -nw">

If not set, C<vi> is used.

=back

=head1 SEE ALSO

L<guestfs(3)>,
L<guestfish(1)>,
L<virt-cat(1)>,
L<Sys::Guestfs(3)>,
L<Sys::Guestfs::Lib(3)>,
L<Sys::Virt(3)>,
L<http://libguestfs.org/>.

=head1 AUTHOR

Richard W.M. Jones L<http://et.redhat.com/~rjones/>

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
