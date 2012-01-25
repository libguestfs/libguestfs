// libguestfs miscellaneous gobject binding tests
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

var g = new Guestfs.Session();

// Test close()
g.close();
var threw = false;
try {
  var v = g.test0rconstoptstring('1');
} catch (error) {
  threw = true;
  if (!error.message.match(/closed/)) {
    print("call after close threw unexpected error: " + error.message);
    fail = true;
  }
}
if (!threw) {
  print("call after closed failed to throw an error");
  fail = true;
}

fail ? 1 : 0;
