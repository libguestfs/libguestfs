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

v = g.test0rint('1');
v == 1 || eq_fail('test0rint', v);
check_error('test0rinterr');

v = g.test0rint64('1');
v == 1 || eq_fail('test0rint64', v);
check_error('test0rint64err');

v = g.test0rbool('true');
v == 1 || eq_fail('test0rbool', v);
check_error('test0rboolerr');

v = g.test0rconststring('1');
v == 'static string' || eq_fail('test0rconststring', v);
check_error('test0rconststringerr');

v = g.test0rconstoptstring('1');
v == 'static string' || eq_fail('test0rconstoptstring', v);
//check_error('test0rconstoptstringerr');

v = g.test0rstring('string');
v == 'string' || eq_fail('test0rstring', v);
check_error('test0rstringerr');

v = g.test0rstringlist('5');
eq = v.length == 5;
for (var i = 0; eq && i < 5; i++) {
  if (v[i] != i) eq = false;
}
eq || eq_fail('test0rstringlist', v.join(' '));
check_error('test0rstringlisterr');

v = g.test0rstruct('1');
v.pv_size == 0 || eq_fail('test0rstruct', v);
check_error('test0rstructerr');

v = g.test0rstructlist('5');
eq = v.length == 5;
for (var i = 0; eq && i < 5; i++) {
  if (v[i].pv_size != i) eq = false;
}
eq || eq_fail('test0rstructlist', v);
check_error('test0rstructlisterr');

v = g.test0rhashtable('5');
eq = true;
for (var i = 0; eq && i < 5; i++) {
  if (v[i] != i) eq = false;
}
eq || eq_fail('test0rhashtable', v);
check_error('test0rhashtableerr');

v = g.test0rbufferout("01234");
eq = v.length == 5;
for (var i = 0; i < v.length; i++) {
  if (v[i] != 48 + i) eq = false; // 48 = ascii '0'
}
eq || eq_fail('test0rbufferout', v);
check_error('test0rbufferouterr');

fail ? 1 : 0;
