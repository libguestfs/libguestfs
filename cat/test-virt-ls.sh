#!/bin/bash -

export LANG=C
set -e

# Read out the test directory using virt-ls.
if [ "$(./virt-ls ../images/fedora.img /bin)" != "ls
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
