# libguestfs Perl bindings -*- perl -*-
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

use strict;
use warnings;

BEGIN {
    use Test::More;
    eval "use Locale::TextDomain";;
    if (exists $INC{"Locale/TextDomain.pm"}) {
        plan tests => 17;
    } else {
        plan skip_all => "no perl-libintl module";
        exit 0;
    }
}

use Sys::Guestfs;
use Sys::Guestfs::Lib;

my $h = Sys::Guestfs->new ();
ok ($h);

$h->add_drive_ro ("../images/test.sqsh");
ok (1);

$h->launch ();
ok (1);
$h->wait_ready ();
ok (1);

$h->mount_vfs ("ro", "squashfs", "/dev/sda", "/");
ok (1);

is (Sys::Guestfs::Lib::file_architecture ($h, "/bin-i586-dynamic"),
    "i386");
is (Sys::Guestfs::Lib::file_architecture ($h, "/bin-sparc-dynamic"),
    "sparc");
is (Sys::Guestfs::Lib::file_architecture ($h, "/bin-win32.exe"),
    "i386");
is (Sys::Guestfs::Lib::file_architecture ($h, "/bin-win64.exe"),
    "x86_64");
is (Sys::Guestfs::Lib::file_architecture ($h, "/bin-x86_64-dynamic"),
    "x86_64");
is (Sys::Guestfs::Lib::file_architecture ($h, "/lib-i586.so"),
    "i386");
is (Sys::Guestfs::Lib::file_architecture ($h, "/lib-sparc.so"),
    "sparc");
is (Sys::Guestfs::Lib::file_architecture ($h, "/lib-win32.dll"),
    "i386");
is (Sys::Guestfs::Lib::file_architecture ($h, "/lib-win64.dll"),
    "x86_64");
is (Sys::Guestfs::Lib::file_architecture ($h, "/lib-x86_64.so"),
    "x86_64");
is (Sys::Guestfs::Lib::file_architecture ($h, "/initrd-x86_64.img"),
    "x86_64");
is (Sys::Guestfs::Lib::file_architecture ($h, "/initrd-x86_64.img.gz"),
    "x86_64");
