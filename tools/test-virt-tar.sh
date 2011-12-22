#!/bin/bash -

export LANG=C
set -e

# Read out the test directory using virt-tar.
./virt-tar -x ../tests/guests/fedora.img /bin test.tar

if [ "$(tar tf test.tar | sort)" != "./
./ls
./test1
./test2
./test3
./test4
./test5
./test6
./test7" ]; then
    echo "$0: error: unexpected output in tarball from virt-tar"
    exit 1
fi

rm test.tar
