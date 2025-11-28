#!/usr/bin/env python3
# libguestfs
# Copyright (C) 2025 Red Hat Inc.
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
#
# Test journal using test data from
# test-data/phony-guests/fedora-journal.tar.xz which is incorporated
# into the Fedora test image in test-data/phony-guests/fedora.img.

import sys
import os
import guestfs

if 'SKIP_TEST_JOURNAL_PY' in os.environ:
    sys.exit(77)

g = guestfs.GuestFS()
g.add_drive("../test-data/phony-guests/fedora.img", readonly=1, format="raw")
g.launch()

# If journal feature is not available, bail.
if not g.feature_available(["journal"]):
    print(f"{sys.argv[0]}: skipping test because journal feature is not available",
          file=sys.stderr)
    sys.exit(77)

# Mount the root filesystem.
g.mount_ro("/dev/VG/Root", "/")

# Open the journal.
g.journal_open("/var/log/journal")

error = None
try:
    # Count the number of journal entries by iterating over them.
    # Save the first few.
    count = 0
    entries = []
    while g.journal_next():
        count += 1
        fields = g.journal_get()
        # Turn the fields into a dict of field name -> data, decoding bytes to strings.
        field_dict = {f['attrname']: f['attrval'].decode('utf-8') for f in fields}
        if count <= 5:
            entries.append(field_dict)

    if count != 2459:
        raise Exception("incorrect # journal entries (got {}, expecting 2459)".format(count))

    # Check a few fields.
    checks = [
        (0, "PRIORITY", "6"),
        (0, "MESSAGE_ID", "ec387f577b844b8fa948f33cad9a75e6"),
        (1, "_TRANSPORT", "driver"),
        (1, "_UID", "0"),
        (2, "_BOOT_ID", "1678ffea9ef14d87a96fa4aecd575842"),
        (2, "_HOSTNAME", "f20rawhidex64.home.annexia.org"),
        (4, "SYSLOG_IDENTIFIER", "kernel")
    ]
    for i, fieldname, expected in checks:
        fields = entries[i]
        if fieldname not in fields:
            raise Exception("field {} does not exist".format(fieldname))
        actual = fields[fieldname]
        if actual != expected:
            raise Exception("unexpected data: got {}={}, expected {}={}".format(fieldname, actual, fieldname, expected))
except Exception as e:
    error = e

g.journal_close()
g.shutdown()
g.close()

if error:
    raise error

sys.exit(0)
