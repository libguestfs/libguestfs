#!/usr/bin/env perl
# Copyright (C) 2019 Red Hat Inc.
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

# Clean up the program name.
my $progname = $0;
$progname =~ s{.*/}{};

my $filename = shift or die "$progname: missing filename";

open(my $fh, '<', $filename) or die "Unable to open file '$filename': $!";

print <<"EOF";
/* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED FROM THE FOLLOWING FILES:
 *          $filename
 * ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
 */

#include <config.h>

#include "p2v.h"

/* Authors involved with virt-v2v and virt-p2v directly. */
const char *authors[] = {
EOF

while (<$fh>) {
  chomp $_;
  printf "  \"%s\",\n", $_;
}

print <<"EOF";
  NULL
};
EOF

close($fh);
