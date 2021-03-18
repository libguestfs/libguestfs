#!/bin/bash -
# libguestfs
# Copyright (C) 2016 Red Hat Inc.
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

# Test the yara_scan command.

set -e

$TEST_FUNCTIONS
skip_if_skipped
skip_unless_feature_available libyara
skip_unless_phony_guest blank-fs.img

rm -f test-yara-rules.yar

/bin/cat << EOF > test-yara-rules.yar
rule TestRule
{
    strings:
        \$my_text_string = "some text"

    condition:
        \$my_text_string
}
EOF

output=$(
guestfish --ro -a ../test-data/phony-guests/blank-fs.img <<EOF
run
mount /dev/sda1 /
write /text.txt "some text"
yara-load test-yara-rules.yar
yara-scan /text.txt
umount /
yara-destroy
EOF
)

echo $output | grep -zq '{ yara_name: /text.txt yara_rule: TestRule }'
if [ $? != 0 ]; then
    echo "$0: TestRule not found in detections list."
    echo "Detections list:"
    echo $output
    exit 1
fi

rm -f test-yara-rules.yar
