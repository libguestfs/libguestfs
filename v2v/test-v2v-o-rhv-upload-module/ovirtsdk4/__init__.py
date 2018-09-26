# -*- python -*-
# Copyright (C) 2018 Red Hat Inc.
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Fake ovirtsdk4 module used as a test harness.
# See v2v/test-v2v-o-rhv-upload.sh

class Error(Exception):
    pass
class NotFoundError(Error):
    pass

class Connection(object):
    def __init__(
            self,
            url = None,
            username = None,
            password = None,
            ca_file = None,
            log = None,
            insecure = False,
    ):
        pass

    def system_service(self):
        return SystemService()

class SystemService(object):
    def data_centers_service(self):
        return DataCentersService()

    def disks_service(self):
        return DisksService()

    def image_transfers_service(self):
        return ImageTransfersService()

    def storage_domains_service(self):
        return StorageDomainsService()

    def vms_service(self):
        return VmsService()

class DataCentersService(object):
    def list(self, search=None, case_sensitive=False):
        return []

class DiskService(object):
    def __init__(self, disk_id):
        self._disk_id = disk_id

    def get(self):
        return types.Disk()

    def remove(self):
        pass

class DisksService(object):
    def add(self, disk=None):
        return disk

    def disk_service(self, disk_id):
        return DiskService(disk_id)

class ImageTransferService(object):
    def __init__(self):
        self._finalized = False

    def get(self):
        if self._finalized:
            raise NotFoundError
        else:
            return types.ImageTransfer()

    def finalize(self):
        self._finalized = True

class ImageTransfersService(object):
    def add(self, transfer):
        return transfer

    def image_transfer_service(self, id):
        return ImageTransferService()

class StorageDomain(object):
    id = "ba87af68-b630-4211-a73a-694c1a689405"

class StorageDomainsService(object):
    def list(self, search=None):
        return [ StorageDomain() ]

class VmsService(object):
    def add(self, vm):
        return vm

    def list(self, search=None):
        return []

# Create a background thread running a web server which is
# simulating the imageio server.

import SimpleHTTPServer
import SocketServer
import threading

class RequestHandler(SimpleHTTPServer.SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_OPTIONS(self):
        self.discard_request()

        # Advertize only zero support.
        content = b'''{ "features": [ "zero" ] }'''
        length = len(content)

        self.send_response(200)
        self.send_header("Content-type", "application/json; charset=UTF-8")
        self.send_header("Content-Length", length)
        self.end_headers()
        self.wfile.write(content)

    # eg. zero request.  Just ignore it.
    def do_PATCH(self):
        self.discard_request()
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # Flush request.  Ignore it.
    def do_PUT(self):
        self.discard_request()
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def discard_request(self):
        length = self.headers.get('Content-Length')
        if length:
            length = int(length)
            content = self.rfile.read(length)

server_address = ("", 0)
# XXX This should test HTTPS, not HTTP, because we are testing a
# different path through the main code.
httpd = SocketServer.TCPServer(server_address, RequestHandler)
imageio_port = httpd.server_address[1]

def server():
    httpd.serve_forever()

thread = threading.Thread(target = server, args = [])
thread.daemon = True
thread.start()
