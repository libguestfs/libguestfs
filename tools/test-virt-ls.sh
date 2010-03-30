#!/bin/bash -

export LANG=C
set -e

# Just a random UUID.
uuid=868b1447-0ec5-41bf-a2e5-6a77a4c9b66f

# Read out the test directory using virt-ls.
if [ "$(./virt-ls test.img /bin)" != "test1
test2
test3
test4
test5
test6
test7" ]; then
    echo "$0: error: unexpected output from virt-ls"
    exit 1
fi
