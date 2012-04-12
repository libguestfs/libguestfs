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

var progress_detected = false;
var trace_detected = false;

// Test events
g.connect('progress', function(session, params) {
  if (params.array_len == 4) {
    // Look for the final progress notification where position = total
    if (params.array[2] == params.array[3] && params.array[2] != 0) {
      progress_detected = true;
    }
  }
});
g.connect('trace', function(session, params) {
  if (params.buf == 'launch') {
    trace_detected = true;
  }
});

g.add_drive('../tests/guests/fedora.img');
g.set_trace(true);
g.launch();
// Fake progress messages for a 5 second event. We do this as launch() will not
// generate any progress messages unless it takes at least 5 seconds.
g.debug('progress', ['5']);
if (!trace_detected) {
  print("failed to detect trace message for launch");
  fail = true;
}
if (!progress_detected) {
  print("failed to detect progress message for launch");
  fail = true;
}

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
