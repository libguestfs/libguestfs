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

# Test the discovery of relationships between LVM PVs, VGs and LVs.

import os
import sys
import re
import guestfs

if os.environ.get('SKIP_TEST_LVM_MAPPING_PY'):
    sys.exit(77)

g = guestfs.GuestFS()

g.add_drive_scratch(256 * 1024 * 1024)

g.launch()

# Create an arrangement of PVs, VGs and LVs.
g.part_init("/dev/sda", "mbr")
g.part_add("/dev/sda", "p", 2048, 128 * 1024 // 2 - 1)
g.part_add("/dev/sda", "p", 128 * 1024 // 2, -64)
g.pvcreate("/dev/sda1")
g.pvcreate("/dev/sda2")
g.vgcreate("VG", ["/dev/sda1", "/dev/sda2"])
g.lvcreate("LV1", "VG", 32)
g.lvcreate("LV2", "VG", 32)
g.lvcreate("LV3", "VG", 32)

# Now let's get the arrangement.
pvs = g.pvs()
lvs = g.lvs()

pvuuids = {}
for pv in pvs:
    uuid = g.pvuuid(pv)
    pvuuids[uuid] = pv

lvuuids = {}
for lv in lvs:
    uuid = g.lvuuid(lv)
    lvuuids[uuid] = lv

# In this case there is only one VG, called "VG", but in a real
# program we'd want to repeat these steps for each VG that you found.
pvuuids_in_VG = g.vgpvuuids("VG")
lvuuids_in_VG = g.vglvuuids("VG")

pvs_in_VG = [pvuuids[uuid] for uuid in pvuuids_in_VG]
pvs_in_VG.sort()

lvs_in_VG = [lvuuids[uuid] for uuid in lvuuids_in_VG]
lvs_in_VG.sort()

if not (len(pvs_in_VG) == 2 and
        re.match(r'/dev/[abce-ln-z]+da1$', pvs_in_VG[0]) and
        re.match(r'/dev/[abce-ln-z]+da2$', pvs_in_VG[1])):
    raise Exception("unexpected set of PVs for volume group VG: [" + ", ".join(pvs_in_VG) + "]")

if not (len(lvs_in_VG) == 3 and
        lvs_in_VG[0] == "/dev/VG/LV1" and
        lvs_in_VG[1] == "/dev/VG/LV2" and
        lvs_in_VG[2] == "/dev/VG/LV3"):
    raise Exception("unexpected set of LVs for volume group VG: [" + ", ".join(lvs_in_VG) + "]")
