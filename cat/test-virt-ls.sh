#!/bin/bash -

export LANG=C
set -e

# Read out the test directory using virt-ls.
if [ "$(./virt-ls ../tests/guests/fedora.img /bin)" != "ls
test1
test2
test3
test4
test5
test6
test7" ]; then
    echo "$0: error: unexpected output from virt-ls"
    exit 1
fi

# Try the -lR option.
output="$(./virt-ls -lR ../tests/guests/fedora.img /boot | awk '{print $1 $2 $4}')"
expected="d0755/boot
d0755/boot/grub
-0644/boot/grub/grub.conf
d0700/boot/lost+found"
if [ "$output" != "$expected" ]; then
    echo "$0: error: unexpected output from virt-ls -lR"
    echo "output: ------------------------------------------"
    echo "$output"
    echo "expected: ----------------------------------------"
    echo "$expected"
    echo "--------------------------------------------------"
    exit 1
fi
