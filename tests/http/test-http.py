# -*- python -*-
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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

import sys
import os
import re
import shutil
from time import sleep
from random import randint

progname = os.path.basename(sys.argv[0])
guestsdir = "../test-data/phony-guests"
listen_addr = "localhost"
#listen_addr = "127.0.0.1"
#listen_addr = ""
connect_addr = "localhost"
#connect_addr = "127.0.0.1"

if os.getenv('SKIP_TEST_HTTP_PY'):
    print >>sys.stderr, \
        ("%s: test skipped because environment variable is set" % progname)
    exit(77)

# Proxy settings can break this test.
del os.environ['http_proxy']

# Remove the stamp file.
stampfile = "%s/stamp-test-http" % os.getcwd()

def unlink_stampfile():
    try:
        os.unlink(stampfile)
    except:
        pass
unlink_stampfile()

# Choose a random port number.
# XXX Should check it is not in use.
port = randint(60000, 65000)

pid = os.fork()
if pid > 0:
    # Parent (client).
    import guestfs

    # Make sure that the child (HTTP server) is killed on exit even if
    # we exit abnormally.
    def cleanup():
        unlink_stampfile()
        if pid > 0:
            os.kill(pid, 15)
    sys.exitfunc = cleanup

    # Wait for the child to touch the stamp file to indicate it has
    # started listening for requests.
    for i in range(1, 10):
        if os.access(stampfile, os.F_OK):
            break
        sleep(1)
        if i == 3:
            print("%s: waiting for the web server to start up ..." % progname)
    if not os.access(stampfile, os.F_OK):
        print >>sys.stderr, \
            ("%s: error: web server process did not start up" % progname)
        exit(1)

    # Create libguestfs handle and connect to the web server.
    g = guestfs.GuestFS(python_return_dict=True)
    server = "%s:%d" % (connect_addr, port)
    g.add_drive_opts("/fedora.img", readonly=True, format="raw",
                     protocol="http", server=[server])
    g.launch()

    # Inspection is quite a thorough test.
    roots = g.inspect_os()
    if len(roots) == 0:
        print >>sys.stderr, \
            ("%s: error: inspection failed to find any OSes in guest image" %
             progname)
        exit(1)
    if len(roots) > 1:
        print >>sys.stderr, \
            ("%s: error: inspection found a multi-boot OS which is not "
             "expected" % progname)
        exit(1)

    type_ = g.inspect_get_type(roots[0])
    distro = g.inspect_get_distro(roots[0])
    if type_ != "linux" or distro != "fedora":
        print >>sys.stderr, \
            ("%s: error: inspection found wrong OS type (%s, %s)" %
             (progname, type_, distro))
        exit(1)

    g.close()

else:
    # Child (HTTP server).
    from BaseHTTPServer import HTTPServer
    from SimpleHTTPServer import SimpleHTTPRequestHandler
    from SocketServer import ThreadingMixIn

    os.chdir(guestsdir)

    class ThreadingServer(ThreadingMixIn, HTTPServer):
        pass

    # This is an extended version of SimpleHTTPRequestHandler that can
    # handle byte ranges.  See also:
    # https://naclports.googlecode.com/svn/trunk/src/httpd.py
    class ByteRangeRequestHandler(SimpleHTTPRequestHandler):
        def do_GET(self):
            if 'Range' in self.headers:
                m = re.match('\s*bytes\s*=\s*(\d+)\s*-\s*(\d+)\s*',
                             self.headers['Range'])
            if m:
                start = int(m.group(1))
                end = int(m.group(2))
                length = end - start + 1
                f = self.send_head_partial(start, length)
                if f:
                    f.seek(start, os.SEEK_CUR)
                    shutil.copyfileobj(f, self.wfile, length)
                    f.close()
                return

            return SimpleHTTPRequestHandler.do_GET(self)

        def send_head_partial(self, offset, length):
            path = self.translate_path(self.path)
            f = None
            if os.path.isdir(path):
                if not self.path.endswith('/'):
                    # redirect browser - doing basically what apache does
                    self.send_response(301)
                    self.send_header("Location", self.path + "/")
                    self.end_headers()
                    return None
                for index in "index.html", "index.htm":
                    index = os.path.join(path, index)
                    if os.path.exists(index):
                        path = index
                        break
                    else:
                        return self.list_directory(path)
            ctype = self.guess_type(path)
            try:
                f = open(path, 'rb')
            except IOError:
                self.send_error(404, "File not found")
                return None
            self.send_response(206, 'Partial content')
            self.send_header("Content-Range", str(offset) + '-' +
                             str(length+offset-1))
            self.send_header("Content-Length", str(length))
            self.send_header("Content-type", ctype)
            fs = os.fstat(f.fileno())
            self.send_header("Last-Modified",
                             self.date_time_string(fs.st_mtime))
            self.end_headers()
            return f

    server_address = (listen_addr, port)
    httpd = ThreadingServer(server_address, ByteRangeRequestHandler)

    sa = httpd.socket.getsockname()
    print("%s: serving %s on %s port %d ..." % (progname,
                                                os.getcwd(), sa[0], sa[1]))

    # Touch the stamp file, which starts the client.
    open(stampfile, 'a')

    # Start serving until killed.
    httpd.serve_forever()

    os._exit(0)
