#!/usr/bin/env python3
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

import os
import sys
import guestfs

prog = os.path.basename(sys.argv[0])
# Because we parse error message strings below.
os.environ["LANG"] = "C"

if os.environ.get("SKIP_TEST_RELABEL_PY"):
    print(f"{prog}: test skipped because environment variable is set.")
    sys.exit(77)

# SELinux labelling won't work (and can be skipped) if SELinux isn't
# installed on the host.
if not os.path.isfile("/etc/selinux/config") or not os.access("/usr/sbin/load_policy", os.X_OK):
    print(f"{prog}: test skipped because SELinux is not available.")
    sys.exit(77)

# Create a filesystem.
g = guestfs.GuestFS(python_return_dict=True)
g.add_drive_scratch(256 * 1024 * 1024)
g.launch()

# If Linux extended attrs aren't available then we cannot test this.
if not g.feature_available(["linuxxattrs"]):
    print(f"{prog}: test skipped because 'linuxxattrs' feature not available.")
    g.close()
    sys.exit(77)

# If SELinux relabelling is not available then we cannot test this.
if not g.feature_available(["selinuxrelabel"]):
    print(f"{prog}: test skipped because 'selinuxrelabel' feature not available.")
    g.close()
    sys.exit(77)

g.part_disk("/dev/sda", "mbr")
g.mkfs("ext4", "/dev/sda1")
g.mount_options("user_xattr", "/dev/sda1", "/")

# Create some files and directories that we want to have relabelled.
g.mkdir("/bin")
g.touch("/bin/ls")
g.mkdir("/etc")
g.mkdir("/tmp")
g.touch("/tmp/test")
g.mkdir("/var")
g.mkdir("/var/log")
g.touch("/var/log/messages")

# Create a spec file.
# This doesn't test the optional file_type field. XXX
# See also file_contexts(5).
g.write("/etc/file_contexts", """/.* system_u:object_r:default_t:s0
/bin/.* system_u:object_r:bin_t:s0
/etc/.* system_u:object_r:etc_t:s0
/etc/file_contexts <<none>>
/tmp/.* <<none>>
/var/.* system_u:object_r:var_t:s0
/var/log/.* system_u:object_r:var_log_t:s0
""")

# Do the relabel.
g.selinux_relabel("/etc/file_contexts", "/", force=True)

# Check the labels were set correctly.
errors = 0

def check_label(file, expected_label):
    global errors
    actual_label = g.lgetxattr(file, "security.selinux")
    # The label returned from lgetxattr has \0 appended.
    if (expected_label + "\0").encode() != actual_label:
        print(
            f"{prog}: expected label on file {file}: "
            f"expected={expected_label} actual={actual_label.decode(errors='ignore')}",
            file=sys.stderr,
        )
        errors += 1

def check_label_none(file):
    global errors
    try:
        r = g.lgetxattr(file, "security.selinux")
        if r:
            print(
                f"{prog}: expecting no label on file {file}, "
                f"but got {r.decode(errors='ignore')}",
                file=sys.stderr,
            )
            errors += 1
    except RuntimeError as e:
        if "No data available" not in str(e):
            print(
                f"{prog}: expecting an error reading label from file {file}, "
                f"but got {e}",
                file=sys.stderr,
            )
            errors += 1

check_label("/bin", "system_u:object_r:default_t:s0")
check_label("/bin/ls", "system_u:object_r:bin_t:s0")
check_label("/etc", "system_u:object_r:default_t:s0")
check_label_none("/etc/file_contexts")
check_label("/tmp", "system_u:object_r:default_t:s0")
check_label_none("/tmp/test")
check_label("/var", "system_u:object_r:default_t:s0")
check_label("/var/log", "system_u:object_r:var_t:s0")
check_label("/var/log/messages", "system_u:object_r:var_log_t:s0")

# Finish up.
g.shutdown()
g.close()

sys.exit(0 if errors == 0 else 1)
