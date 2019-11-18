# -*- python -*-
# oVirt or RHV upload nbdkit plugin used by ‘virt-v2v -o rhv-upload’
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

import builtins
import json
import logging
import socket
import ssl
import sys
import time

from http.client import HTTPSConnection, HTTPConnection
from urllib.parse import urlparse

import ovirtsdk4 as sdk
import ovirtsdk4.types as types

# Timeout to wait for oVirt disks to change status, or the transfer
# object to finish initializing [seconds].
timeout = 5*60

# Parameters are passed in via a JSON doc from the OCaml code.
# Because this Python code ships embedded inside virt-v2v there
# is no formal API here.
params = None

def config(key, value):
    global params

    if key == "params":
        with builtins.open(value, 'r') as fp:
            params = json.load(fp)
    else:
        raise RuntimeError("unknown configuration key '%s'" % key)

def config_complete():
    if params is None:
        raise RuntimeError("missing configuration parameters")

def debug(s):
    if params['verbose']:
        print(s, file=sys.stderr)
        sys.stderr.flush()

def find_host(connection):
    """Return the current host object or None."""
    try:
        with builtins.open("/etc/vdsm/vdsm.id") as f:
            vdsm_id = f.readline().strip()
    except Exception as e:
        # This is most likely not an oVirt host.
        debug("cannot read /etc/vdsm/vdsm.id, using any host: %s" % e)
        return None

    debug("hw_id = %r" % vdsm_id)

    system_service = connection.system_service()
    storage_name = params['output_storage']
    data_centers = system_service.data_centers_service().list(
        search='storage.name=%s' % storage_name,
        case_sensitive=True,
    )
    if len(data_centers) == 0:
        # The storage domain is not attached to a datacenter
        # (shouldn't happen, would fail on disk creation).
        debug("storange domain (%s) is not attached to a DC" % storage_name)
        return None

    datacenter = data_centers[0]
    debug("datacenter = %s" % datacenter.name)

    hosts_service = system_service.hosts_service()
    hosts = hosts_service.list(
        search="hw_id=%s and datacenter=%s and status=Up"
               % (vdsm_id, datacenter.name),
        case_sensitive=True,
    )
    if len(hosts) == 0:
        # Couldn't find a host that's fulfilling the following criteria:
        # - 'hw_id' equals to 'vdsm_id'
        # - Its status is 'Up'
        # - Belongs to the storage domain's datacenter
        debug("cannot find a running host with hw_id=%r, "
              "that belongs to datacenter '%s', "
              "using any host" % (vdsm_id, datacenter.name))
        return None

    host = hosts[0]
    debug("host.id = %r" % host.id)

    return types.Host(id = host.id)

def open(readonly):
    # Parse out the username from the output_conn URL.
    parsed = urlparse(params['output_conn'])
    username = parsed.username or "admin@internal"

    # Read the password from file.
    with builtins.open(params['output_password'], 'r') as fp:
        password = fp.read()
    password = password.rstrip()

    # Connect to the server.
    connection = sdk.Connection(
        url = params['output_conn'],
        username = username,
        password = password,
        ca_file = params['rhv_cafile'],
        log = logging.getLogger(),
        insecure = params['insecure'],
    )

    system_service = connection.system_service()

    # Create the disk.
    disks_service = system_service.disks_service()
    if params['disk_format'] == "raw":
        disk_format = types.DiskFormat.RAW
    else:
        disk_format = types.DiskFormat.COW
    disk = disks_service.add(
        disk = types.Disk(
            # The ID is optional.
            id = params.get('rhv_disk_uuid'),
            name = params['disk_name'],
            description = "Uploaded by virt-v2v",
            format = disk_format,
            initial_size = params['disk_size'],
            provisioned_size = params['disk_size'],
            # XXX Ignores params['output_sparse'].
            # Handling this properly will be complex, see:
            # https://www.redhat.com/archives/libguestfs/2018-March/msg00177.html
            sparse = True,
            storage_domains = [
                types.StorageDomain(
                    name = params['output_storage'],
                )
            ],
        )
    )

    # Wait till the disk is up, as the transfer can't start if the
    # disk is locked:
    disk_service = disks_service.disk_service(disk.id)
    debug("disk.id = %r" % disk.id)

    endt = time.time() + timeout
    while True:
        time.sleep(1)
        disk = disk_service.get()
        if disk.status == types.DiskStatus.OK:
            break
        if time.time() > endt:
            raise RuntimeError("timed out waiting for disk to become unlocked")

    # Get a reference to the transfer service.
    transfers_service = system_service.image_transfers_service()

    # Create a new image transfer, using the local host is possible.
    host = find_host(connection) if params['rhv_direct'] else None
    transfer = transfers_service.add(
        types.ImageTransfer(
            disk = types.Disk(id = disk.id),
            host = host,
            inactivity_timeout = 3600,
        )
    )
    debug("transfer.id = %r" % transfer.id)

    # Get a reference to the created transfer service.
    transfer_service = transfers_service.image_transfer_service(transfer.id)

    # After adding a new transfer for the disk, the transfer's status
    # will be INITIALIZING.  Wait until the init phase is over. The
    # actual transfer can start when its status is "Transferring".
    endt = time.time() + timeout
    while True:
        transfer = transfer_service.get()
        if transfer.phase != types.ImageTransferPhase.INITIALIZING:
            break
        if time.time() > endt:
            raise RuntimeError(
                "timed out waiting for transfer %s status != INITIALIZING"
                % transfer.id)

        time.sleep(1)

    # Now we have permission to start the transfer.
    if params['rhv_direct']:
        if transfer.transfer_url is None:
            raise RuntimeError("direct upload to host not supported, "
                               "requires ovirt-engine >= 4.2 and only works "
                               "when virt-v2v is run within the oVirt/RHV "
                               "environment, eg. on an oVirt node.")
        destination_url = urlparse(transfer.transfer_url)
    else:
        destination_url = urlparse(transfer.proxy_url)

    if destination_url.scheme == "https":
        context = \
            ssl.create_default_context(purpose = ssl.Purpose.SERVER_AUTH,
                                       cafile = params['rhv_cafile'])
        if params['insecure']:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        http = HTTPSConnection(
            destination_url.hostname,
            destination_url.port,
            context = context
        )
    elif destination_url.scheme == "http":
        http = HTTPConnection(
            destination_url.hostname,
            destination_url.port,
        )
    else:
        raise RuntimeError("unknown URL scheme (%s)" % destination_url.scheme)

    # The first request is to fetch the features of the server.

    # Authentication was needed only for GET and PUT requests when
    # communicating with old imageio-proxy.
    needs_auth = not params['rhv_direct']

    can_flush = False
    can_trim = False
    can_zero = False
    unix_socket = None

    http.request("OPTIONS", destination_url.path)
    r = http.getresponse()
    data = r.read()

    if r.status == 200:
        # New imageio never needs authentication.
        needs_auth = False

        j = json.loads(data)
        can_flush = "flush" in j['features']
        can_trim = "trim" in j['features']
        can_zero = "zero" in j['features']
        unix_socket = j.get('unix_socket')

    # Old imageio servers returned either 405 Method Not Allowed or
    # 204 No Content (with an empty body).  If we see that we leave
    # all the features as False and they will be emulated.
    elif r.status == 405 or r.status == 204:
        pass

    else:
        raise RuntimeError("could not use OPTIONS request: %d: %s" %
                           (r.status, r.reason))

    debug("imageio features: flush=%r trim=%r zero=%r unix_socket=%r" %
          (can_flush, can_trim, can_zero, unix_socket))

    # If we are connected to imageio on the local host and the
    # transfer features a unix_socket then we can reconnect to that.
    if host is not None and unix_socket is not None:
        try:
            http = UnixHTTPConnection(unix_socket)
        except Exception as e:
            # Very unlikely failure, but we can recover by using the https
            # connection.
            debug("cannot create unix socket connection, using https: %s" % e)
        else:
            debug("optimizing connection using unix socket %r" % unix_socket)

    # Save everything we need to make requests in the handle.
    return {
        'can_flush': can_flush,
        'can_trim': can_trim,
        'can_zero': can_zero,
        'connection': connection,
        'disk': disk,
        'disk_service': disk_service,
        'failed': False,
        'highestwrite': 0,
        'http': http,
        'needs_auth': needs_auth,
        'path': destination_url.path,
        'transfer': transfer,
        'transfer_service': transfer_service,
    }

def can_trim(h):
    return h['can_trim']

def can_flush(h):
    return h['can_flush']

def get_size(h):
    return params['disk_size']

# Any unexpected HTTP response status from the server will end up
# calling this function which logs the full error, pauses the
# transfer, sets the failed state, and raises a RuntimeError
# exception.
def request_failed(h, r, msg):
    # Setting the failed flag in the handle causes the disk to be
    # cleaned up on close.
    h['failed'] = True
    h['transfer_service'].pause()

    status = r.status
    reason = r.reason
    try:
        body = r.read()
    except EnvironmentError as e:
        body = "(Unable to read response body: %s)" % e

    # Log the full error if we're verbose.
    debug("unexpected response from imageio server:")
    debug(msg)
    debug("%d: %s" % (status, reason))
    debug(body)

    # Only a short error is included in the exception.
    raise RuntimeError("%s: %d %s: %r" % (msg, status, reason, body[:200]))

# For documentation see:
# https://github.com/oVirt/ovirt-imageio/blob/master/docs/random-io.md
# For examples of working code to read/write from the server, see:
# https://github.com/oVirt/ovirt-imageio/blob/master/daemon/test/server_test.py

def pread(h, count, offset):
    http = h['http']
    transfer = h['transfer']

    headers = {"Range": "bytes=%d-%d" % (offset, offset+count-1)}
    if h['needs_auth']:
        headers["Authorization"] = transfer.signed_ticket

    http.request("GET", h['path'], headers=headers)

    r = http.getresponse()
    # 206 = HTTP Partial Content.
    if r.status != 206:
        request_failed(h, r,
                       "could not read sector offset %d size %d" %
                       (offset, count))

    return r.read()

def pwrite(h, buf, offset):
    http = h['http']
    transfer = h['transfer']

    count = len(buf)
    h['highestwrite'] = max(h['highestwrite'], offset+count)

    http.putrequest("PUT", h['path'] + "?flush=n")
    if h['needs_auth']:
        http.putheader("Authorization", transfer.signed_ticket)
    # The oVirt server only uses the first part of the range, and the
    # content-length.
    http.putheader("Content-Range", "bytes %d-%d/*" % (offset, offset+count-1))
    http.putheader("Content-Length", str(count))
    http.endheaders()

    try:
        http.send(buf)
    except BrokenPipeError:
        pass

    r = http.getresponse()
    if r.status != 200:
        request_failed(h, r,
                       "could not write sector offset %d size %d" %
                       (offset, count))

    r.read()

def zero(h, count, offset, may_trim):
    http = h['http']

    # Unlike the trim and flush calls, there is no 'can_zero' method
    # so nbdkit could call this even if the server doesn't support
    # zeroing.  If this is the case we must emulate.
    if not h['can_zero']:
        emulate_zero(h, count, offset)
        return

    # Construct the JSON request for zeroing.
    buf = json.dumps({'op': "zero",
                      'offset': offset,
                      'size': count,
                      'flush': False}).encode()

    headers = {"Content-Type": "application/json",
               "Content-Length": str(len(buf))}

    http.request("PATCH", h['path'], body=buf, headers=headers)

    r = http.getresponse()
    if r.status != 200:
        request_failed(h, r,
                       "could not zero sector offset %d size %d" %
                       (offset, count))

    r.read()

def emulate_zero(h, count, offset):
    http = h['http']
    transfer = h['transfer']

    # qemu-img convert starts by trying to zero/trim the whole device.
    # Since we've just created a new disk it's safe to ignore these
    # requests as long as they are smaller than the highest write seen.
    # After that we must emulate them with writes.
    if offset+count < h['highestwrite']:
        http.putrequest("PUT", h['path'])
        if h['needs_auth']:
            http.putheader("Authorization", transfer.signed_ticket)
        http.putheader("Content-Range",
                       "bytes %d-%d/*" % (offset, offset+count-1))
        http.putheader("Content-Length", str(count))
        http.endheaders()

        try:
            buf = bytearray(128*1024)
            while count > len(buf):
                http.send(buf)
                count -= len(buf)
            http.send(memoryview(buf)[:count])
        except BrokenPipeError:
            pass

        r = http.getresponse()
        if r.status != 200:
            request_failed(h, r,
                           "could not write zeroes offset %d size %d" %
                           (offset, count))

        r.read()

def trim(h, count, offset):
    http = h['http']

    # Construct the JSON request for trimming.
    buf = json.dumps({'op': "trim",
                      'offset': offset,
                      'size': count,
                      'flush': False}).encode()

    headers = {"Content-Type": "application/json",
               "Content-Length": str(len(buf))}

    http.request("PATCH", h['path'], body=buf, headers=headers)

    r = http.getresponse()
    if r.status != 200:
        request_failed(h, r,
                       "could not trim sector offset %d size %d" %
                       (offset, count))

    r.read()

def flush(h):
    http = h['http']

    # Construct the JSON request for flushing.
    buf = json.dumps({'op': "flush"}).encode()

    headers = {"Content-Type": "application/json",
               "Content-Length": str(len(buf))}

    http.request("PATCH", h['path'], body=buf, headers=headers)

    r = http.getresponse()
    if r.status != 200:
        request_failed(h, r, "could not flush")

    r.read()

def delete_disk_on_failure(h):
    disk_service = h['disk_service']
    disk_service.remove()

def close(h):
    http = h['http']
    connection = h['connection']

    # This is sometimes necessary because python doesn't set up
    # sys.stderr to be line buffered and so debug, errors or
    # exceptions printed previously might not be emitted before the
    # plugin exits.
    sys.stderr.flush()

    # If the connection failed earlier ensure we clean up the disk.
    if h['failed']:
        delete_disk_on_failure(h)
        connection.close()
        return

    try:
        # Issue a flush request on close so that the data is written to
        # persistent store before we create the VM.
        if h['can_flush']:
            flush(h)

        http.close()

        disk = h['disk']
        transfer_service = h['transfer_service']

        transfer_service.finalize()

        # Wait until the transfer disk job is completed since
        # only then we can be sure the disk is unlocked.  As this
        # code is not very clear, what's happening is that we are
        # waiting for the transfer object to cease to exist, which
        # falls through to the exception case and then we can
        # continue.
        disk_id = disk.id
        start = time.time()
        try:
            while True:
                time.sleep(1)
                disk_service = h['disk_service']
                disk = disk_service.get()
                if disk.status == types.DiskStatus.LOCKED:
                    if time.time() > start + timeout:
                        raise RuntimeError("timed out waiting for transfer "
                                           "to finalize")
                    continue
                if disk.status == types.DiskStatus.OK:
                    debug("finalized after %s seconds" % (time.time() - start))
                    break
        except sdk.NotFoundError:
            raise RuntimeError("transfer failed: disk %s not found" % disk_id)

        # Write the disk ID file.  Only do this on successful completion.
        with builtins.open(params['diskid_file'], 'w') as fp:
            fp.write(disk.id)

    except:
        # Otherwise on any failure we must clean up the disk.
        delete_disk_on_failure(h)
        raise

    connection.close()

# Modify http.client.HTTPConnection to work over a Unix domain socket.
# Derived from uhttplib written by Erik van Zijst under an MIT license.
# (https://pypi.org/project/uhttplib/)
# Ported to Python 3 by Irit Goihman.

class UnsupportedError(Exception):
    pass

class UnixHTTPConnection(HTTPConnection):
    def __init__(self, path, timeout=socket._GLOBAL_DEFAULT_TIMEOUT):
        self.path = path
        HTTPConnection.__init__(self, "localhost", timeout=timeout)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if self.timeout is not socket._GLOBAL_DEFAULT_TIMEOUT:
            self.sock.settimeout(timeout)
        self.sock.connect(self.path)
