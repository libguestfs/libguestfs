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

import datetime
import json
import os
import sys
import unittest

exe = "tools_messages_tests"

if sys.version_info >= (3, 4):
    def set_fd_inheritable(fd):
        os.set_inheritable(fd, True)
else:
    def set_fd_inheritable(fd):
        pass


if sys.version_info >= (3, 0):
    def fdopen(fd, mode):
        return open(fd, mode)

    def isModuleInstalled(mod):
        import importlib.util
        return bool(importlib.util.find_spec(mod))
else:
    def fdopen(fd, mode):
        return os.fdopen(fd, mode)

    def isModuleInstalled(mod):
        import imp
        try:
            imp.find_module(mod)
            return True
        except ImportError:
            return False


def skipUnlessHasModule(mod):
    if not isModuleInstalled(mod):
        return unittest.skip("%s not available" % mod)
    return lambda func: func


def iterload(stream):
    dec = json.JSONDecoder()
    for line in stream:
        yield dec.raw_decode(line)


def loadJsonFromCommand(extraargs):
    r, w = os.pipe()
    set_fd_inheritable(r)
    r = fdopen(r, "r")
    set_fd_inheritable(w)
    w = fdopen(w, "w")
    pid = os.fork()
    if pid:
        w.close()
        l = list(iterload(r))
        l = [o[0] for o in l]
        r.close()
        return l
    else:
        r.close()
        args = ["tools_messages_tests",
                "--machine-readable=fd:%d" % w.fileno()] + extraargs
        os.execvp("./" + exe, args)


@skipUnlessHasModule('iso8601')
class TestParseToolsMessages(unittest.TestCase):
    def check_json(self, json, typ, msg):
        import iso8601
        # Check the type.
        jsontype = json.pop("type")
        self.assertEqual(jsontype, typ)
        # Check the message.
        jsonmsg = json.pop("message")
        self.assertEqual(jsonmsg, msg)
        # Check the timestamp.
        jsonts = json.pop("timestamp")
        dt = iso8601.parse_date(jsonts)
        now = datetime.datetime.now(dt.tzinfo)
        self.assertGreater(now, dt)
        # Check there are no more keys left (and thus not previously tested).
        self.assertEqual(len(json), 0)

    def test_messages(self):
        objects = loadJsonFromCommand([])
        self.assertEqual(len(objects), 4)
        self.check_json(objects[0], "message", "Starting")
        self.check_json(objects[1], "info", "An information message")
        self.check_json(objects[2], "warning", "Warning: message here")
        self.check_json(objects[3], "message", "Finishing")

    def test_error(self):
        objects = loadJsonFromCommand(["--error"])
        self.assertEqual(len(objects), 1)
        self.check_json(objects[0], "error", "Error!")


if __name__ == '__main__':
    unittest.main()
