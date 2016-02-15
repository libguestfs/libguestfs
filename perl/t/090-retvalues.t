# libguestfs Perl bindings -*- perl -*-
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
use Test::More tests => 42;

use Sys::Guestfs;

my $g = Sys::Guestfs->new ();
ok ($g);

# rint
is ($g->internal_test_rint ("10"), 10, "rint");
eval {
  my $foo = $g->internal_test_rinterr ();
};
like ($@, qr/error/, "rinterr");

# rint64
is ($g->internal_test_rint64 ("10"), 10, "rint64");
eval {
  my $foo = $g->internal_test_rint64err ();
};
like ($@, qr/error/, "rint64err");

# rbool
is ($g->internal_test_rbool ("true"), 1, "rbool/true");
is ($g->internal_test_rbool ("false"), 0, "rbool/false");
eval {
  my $foo = $g->internal_test_rboolerr ();
};
like ($@, qr/error/, "rboolerr");

# rconststring
is ($g->internal_test_rconststring ("test"), "static string", "rconststring");
eval {
  my $foo = $g->internal_test_rconststringerr ();
};
like ($@, qr/error/, "rconststringerr");

# rconstoptstring
is ($g->internal_test_rconstoptstring ("test"), "static string", "rconstoptstring");
# this never fails
eval {
  my $foo = $g->internal_test_rconstoptstringerr ();
};
unlike ($@, qr/error/, "rconstoptstringerr");

# rstring
is ($g->internal_test_rstring ("test"), "test", "rstring");
eval {
  my $foo = $g->internal_test_rstringerr ();
};
like ($@, qr/error/, "rstringerr");

# rstringlist
my @l = $g->internal_test_rstringlist ("0");
is (@l, 0, "rstringlist/empty");
@l = $g->internal_test_rstringlist ("5");
is (@l, 5, "rstringlist/5/size");
for (my $i = 0; $i < @l; $i++) {
  is ($l[$i], $i, "rstringlist/5/$i");
}
eval {
  my $foo = $g->internal_test_rstringlisterr ();
};
like ($@, qr/error/, "rstringlisterr");

# rstruct
my %s = $g->internal_test_rstruct ("unused");
is ($s{'pv_name'}, "pv0", "rstruct/0");
eval {
  my $foo = $g->internal_test_rstructerr ();
};
like ($@, qr/error/, "rstructerr");

# rstructlist
my @sl = $g->internal_test_rstructlist ("0");
is (@sl, 0, "rstructlist/empty");
@sl = $g->internal_test_rstructlist ("5");
is (@sl, 5, "rstructlist/5/size");
for (my $i = 0; $i < @sl; $i++) {
  is ($sl[$i]{'pv_name'}, "pv$i", "rstructlist/5/$i");
}
eval {
  my $foo = $g->internal_test_rstructlisterr ();
};
like ($@, qr/error/, "rstructlisterr");

# rhashtable
my %sl = $g->internal_test_rhashtable ("0");
my $sls = keys %sl;
is ($sls, 0, "rhashtable/empty");
%sl = $g->internal_test_rhashtable ("5");
$sls = keys %sl;
is ($sls, 5, "rhashtable/5/size");
for (my $i = 0; $i < $sls; $i++) {
  is ($sl{$i}, $i, "rhashtable/5/$i");
}
eval {
  my $foo = $g->internal_test_rhashtableerr ();
};
like ($@, qr/error/, "rhashtableerr");

# rbufferout
is ($g->internal_test_rbufferout ("test"), "test", "rbufferout");
eval {
  my $foo = $g->internal_test_rbufferouterr ();
};
like ($@, qr/error/, "rbufferouterr");
