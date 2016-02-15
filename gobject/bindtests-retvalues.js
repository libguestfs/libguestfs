// libguestfs manually written gobject binding tests
// Copyright (C) 2012 Red Hat Inc.
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

const Guestfs = imports.gi.Guestfs;

var fail = false;

function check_error(f) {
  var threw = false;

  try {
    g[f]();
  } catch (error) {
    threw = true;
    if (!error.message.match(/error$/)) {
      print(f + " threw unexpected error: " + error.message);
      fail = true;
    }
  }
  if (!threw) {
    print(f + " failed to throw an error");
    fail = true;
  }
}

function eq_fail(f, v) {
  print(f + " returned unexpected value: " + v);
  fail = true;
}

var g = new Guestfs.Session();

var v;
var eq;

v = g.internal_test_rint('1');
v == 1 || eq_fail('internal_test_rint', v);
check_error('internal_test_rinterr');

v = g.internal_test_rint64('1');
v == 1 || eq_fail('internal_test_rint64', v);
check_error('internal_test_rint64err');

v = g.internal_test_rbool('true');
v == 1 || eq_fail('internal_test_rbool', v);
check_error('internal_test_rboolerr');

v = g.internal_test_rconststring('1');
v == 'static string' || eq_fail('internal_test_rconststring', v);
check_error('internal_test_rconststringerr');

v = g.internal_test_rconstoptstring('1');
v == 'static string' || eq_fail('internal_test_rconstoptstring', v);
//check_error('internal_test_rconstoptstringerr');

v = g.internal_test_rstring('string');
v == 'string' || eq_fail('internal_test_rstring', v);
check_error('internal_test_rstringerr');

v = g.internal_test_rstringlist('5');
eq = v.length == 5;
for (var i = 0; eq && i < 5; i++) {
  if (v[i] != i) eq = false;
}
eq || eq_fail('internal_test_rstringlist', v.join(' '));
check_error('internal_test_rstringlisterr');

v = g.internal_test_rstruct('1');
v.pv_size == 0 || eq_fail('internal_test_rstruct', v);
check_error('internal_test_rstructerr');

v = g.internal_test_rstructlist('5');
eq = v.length == 5;
for (var i = 0; eq && i < 5; i++) {
  if (v[i].pv_size != i) eq = false;
}
eq || eq_fail('internal_test_rstructlist', v);
check_error('internal_test_rstructlisterr');

v = g.internal_test_rhashtable('5');
eq = true;
for (var i = 0; eq && i < 5; i++) {
  if (v[i] != i) eq = false;
}
eq || eq_fail('internal_test_rhashtable', v);
check_error('internal_test_rhashtableerr');

v = g.internal_test_rbufferout("01234");
eq = v.length == 5;
for (var i = 0; i < v.length; i++) {
  if (v[i] != 48 + i) eq = false; // 48 = ascii '0'
}
eq || eq_fail('internal_test_rbufferout', v);
check_error('internal_test_rbufferouterr');

fail ? 1 : 0;
