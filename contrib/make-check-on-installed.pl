#!/usr/bin/perl -w
# libguestfs
# Copyright (C) 2009-2012 Red Hat Inc.
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

# This script allows you to run the test suite ('make check' etc) on
# an installed copy of libguestfs.  Currently only RPM installs are
# supported, but adding support for dpkg would be relatively
# straightforward.  It works by examining the installed packages, and
# copying binaries (eg. '/usr/bin/guestfish') and libraries into the
# correct place in the local directory.
#
# * You MUST have the full source tree unpacked locally.  Either
#   use the same source tarball as the version you are testing, or
#   check it out from git and 'git-reset' to the right version tag.
#
# * You MUST do a successful local build from source before using
#   this script (ie. './autogen.sh && make').
#
# Run the script from the top builddir.  Usually:
#
#   ./contrib/make-check-on-installed.pl
#
# If the script runs successfully, then run the test suite as normal:
#
#   make check
#   make extra-tests
#
# To switch back to running the test suite on the locally built
# version, do:
#
#   make clean && make

use strict;

die "wrong directory -- read the file before running\n" unless -f "BUGS";

my $cmd;

# Remove all libtool crappage.
$cmd = "find -name 'lt-*' | grep -v '/tests/' | grep '/.libs/lt-' | xargs -r rm";
system ($cmd) == 0 or die "$cmd: failed\n";

$cmd = "find -name 'lib*.so*' | grep -v '/tests/' | grep '/.libs/lib' | xargs -r rm";
system ($cmd) == 0 or die "$cmd: failed\n";

# Map of installed file to local file.  Key is a regexp.
# Remember that ONLY libraries and binaries need to be copied.
my %mapping = (
    '/bin/erl-guestfs$' => "erlang",
    '/bin/libguestfs-test-tool$' => "test-tool",
    '/bin/guestfish$' => "fish",
    '/bin/guestmount$' => "fuse",
    '/bin/virt-alignment-scan$' => "align",
    '/bin/virt-cat$' => "cat",
    '/bin/virt-copy-in$' => "fish",
    '/bin/virt-copy-out$' => "fish",
    '/bin/virt-df$' => "df",
    '/bin/virt-edit$' => "edit",
    '/bin/virt-filesystems$' => "cat",
    '/bin/virt-format$' => "format",
    '/bin/virt-inspector$' => "inspector",
    '/bin/virt-list-filesystems$' => "tools",
    '/bin/virt-list-partitions$' => "tools",
    '/bin/virt-ls$' => "cat",
    '/bin/virt-make-fs$' => "tools",
    '/bin/virt-rescue$' => "rescue",
    '/bin/virt-resize$' => "resize",
    '/bin/virt-sparsify$' => "sparsify",
    '/bin/virt-sysprep$' => "sysprep",
    '/bin/virt-tar$' => "tools",
    '/bin/virt-tar-in$' => "fish",
    '/bin/virt-tar-out$' => "fish",
    '/bin/virt-win-reg$' => "tools",

    # Ignore this because the daemon is included in the appliance.
    '/sbin/guestfsd$' => "IGNORE",

    '/erlang/lib/libguestfs-.*/ebin/guestfs\.beam$' => "erlang",

    '/girepository-1\.0/Guestfs-1\.0\.typelib$' => "gobject",
    '/gir-1.0/Guestfs-1.0.gir$' => "gobject",

    '/guestfs/supermin.d/.*' => "appliance/supermin.d",

    '/java/libguestfs-.*\.jar$' => "java",

    '/libguestfs\.so.*' => "src/.libs",
    '/libguestfs_jni\.so.*' => "java/.libs",
    '/libguestfs-gobject-1\.0\.so.*' => "gobject/.libs",

    '/ocaml/.*\.cmi$' => "IGNORE",
    '/ocaml/.*\.cmo$' => "ocaml",
    '/ocaml/.*\.cmx$' => "ocaml",
    '/ocaml/.*\.cma$' => "ocaml",
    '/ocaml/.*\.cmxa$' => "ocaml",
    '/ocaml/.*\.a$' => "ocaml",
    '/ocaml/.*\.so$' => "ocaml",
    '/ocaml/.*\.so.owner$' => "IGNORE",
    '/ocaml/.*META$' => "IGNORE",
    '/ocaml/.*/guestfs\.mli$' => "IGNORE",
    '/ocaml/.*/guestfs\.ml$' => "IGNORE",

    '/perl5/.*/Guestfs\.so$' => "perl/blib/arch/auto/Sys/Guestfs",
    '/perl5/.*/Guestfs.pm$' => "perl/blib/lib/Sys/Guestfs.pm",
    '/perl5/.*/Lib.pm$' => "perl/blib/lib/Sys/Guestfs/Lib.pm",

    '/php/modules/guestfs_php\.so$' => "php/extension/modules",
    '/php/modules/guestfs_php\.so$' => "php/extension/.libs",

    '/python.*/libguestfsmod\.so$' => "python/.libs",
    '/python.*/guestfs\.py' => "IGNORE",
    '/python.*/guestfs\.pyc$' => "python/guestfs.pyc",
    '/python.*/guestfs\.pyo$' => "python/guestfs.pyo",

    '/ruby/.*/_guestfs\.so$' => "ruby/ext/guestfs",
    '/ruby/.*/guestfs\.rb$' => "IGNORE",

    '/share/doc/' => "IGNORE",
    '/share/javadoc/' => "IGNORE",
    '/share/locale/' => "IGNORE",
    '/share/man/' => "IGNORE",

    '^/etc/' => "IGNORE",
    '/systemd/' => "IGNORE",
    '/include/guestfs\.h$' => "IGNORE",
    '/include/guestfs-gobject\.h$' => "IGNORE",
    '/libguestfs\.pc$' => "IGNORE",
);

# Get list of installed files.
$cmd = 'rpm -ql $(rpm -qa | grep -i guestf | grep -v debug) | sort';
my @files;
open CMD, "$cmd |" or die "$cmd: $!";
while (<CMD>) {
    chomp;
    push @files, $_;
}
close CMD;

# Now try to map (copy) installed files to the local equivalents.
foreach my $file (@files) {
    my $match = 0;
    foreach my $regexp (keys %mapping) {
        if ($file =~ m/$regexp/) {
            my $dest = $mapping{$regexp};
            if ($dest ne "IGNORE") {
                # Make destination writable if it's a file.
                chmod 0644, "$dest" if -f "$dest" && ! -w "$dest";

                # Copy file to destination.
                $cmd = "cp '$file' '$dest'";
                system ($cmd) == 0 or die "$cmd: failed\n";
                print "$file => $dest\n";
            }
            $match++;
        }
    }
    if ($match == 0) {
        if (! -d $file) {
            warn "WARNING: file '$file' is unmatched\n"
        }
    }
}
