#!/usr/bin/env perl
# Copyright (C) 2016 Red Hat Inc.
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;

use Sys::Guestfs;

my $prog = $0;
$prog =~ s{.*/}{};

# Because we parse error message strings below.
$ENV{LANG} = "C";

if ($ENV{"SKIP_TEST_RELABEL_PL"}) {
    print "$prog: test skipped because environment variable is set.\n";
    exit 77
}

# SELinux labelling won't work (and can be skipped) if SELinux isn't
# installed on the host.
if (! -f "/etc/selinux/config" || ! -x "/usr/sbin/load_policy") {
    print "$prog: test skipped because SELinux is not available.\n";
    exit 77
}

# Create a filesystem.
my $g = Sys::Guestfs->new ();

$g->add_drive_scratch (256*1024*1024);
$g->launch ();

# If Linux extended attrs aren't available then we cannot test this.
unless ($g->feature_available (["linuxxattrs"])) {
    print "$prog: test skipped because 'linuxxattrs' feature not available.\n";
    $g->close ();
    exit 77
}

$g->part_disk ("/dev/sda", "mbr");
$g->mkfs ("ext4", "/dev/sda1");

$g->mount_options ("user_xattr", "/dev/sda1", "/");

# Create some files and directories that we want to have relabelled.
$g->mkdir ("/bin");
$g->touch ("/bin/ls");
$g->mkdir ("/etc");
$g->mkdir ("/tmp");
$g->touch ("/tmp/test");
$g->mkdir ("/var");
$g->mkdir ("/var/log");
$g->touch ("/var/log/messages");

# Create a spec file.
# This doesn't test the optional file_type field. XXX
# See also file_contexts(5).
$g->write ("/etc/file_contexts", <<'EOF');
/.*                system_u:object_r:default_t:s0
/bin/.*            system_u:object_r:bin_t:s0
/etc/.*            system_u:object_r:etc_t:s0
/etc/file_contexts <<none>>
/tmp/.*            <<none>>
/var/.*            system_u:object_r:var_t:s0
/var/log/.*        system_u:object_r:var_log_t:s0
EOF

# Do the relabel.
$g->selinux_relabel ("/etc/file_contexts", "/", force => 1);

# Check the labels were set correctly.
my $errors = 0;

sub check_label
{
    my $file = shift;
    my $expected_label = shift;

    my $actual_label = $g->lgetxattr ($file, "security.selinux");
    # The label returned from lgetxattr has \0 appended.
    if ("$expected_label\0" ne $actual_label) {
        print STDERR "$prog: expected label on file $file: expected=$expected_label actual=$actual_label\n";
        $errors++;
    }
}

sub check_label_none
{
    my $file = shift;
    my $r;

    eval {
        $r = $g->lgetxattr ($file, "security.selinux");
    };
    if (defined $r) {
        print STDERR "$prog: expecting no label on file $file, but got $r\n";
        $errors++;
    } elsif ($@) {
        if ($@ !~ /No data available/) {
            print STDERR "$prog: expecting an error reading label from file $file, but got $@\n";
            $errors++;
        }
    }
}

check_label ("/bin", "system_u:object_r:default_t:s0");
check_label ("/bin/ls", "system_u:object_r:bin_t:s0");
check_label ("/etc", "system_u:object_r:default_t:s0");
check_label_none ("/etc/file_contexts");
check_label ("/tmp", "system_u:object_r:default_t:s0");
check_label_none ("/tmp/test");
check_label ("/var", "system_u:object_r:default_t:s0");
check_label ("/var/log", "system_u:object_r:var_t:s0");
check_label ("/var/log/messages", "system_u:object_r:var_log_t:s0");

# Finish up.
$g->shutdown ();
$g->close ();

exit ($errors == 0 ? 0 : 1);
