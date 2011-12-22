#!/bin/bash -

export LANG=C
set -e

# Read out the test files from the image using virt-cat.
if [ "$(./virt-cat ../tests/guests/fedora.img /etc/test1)" != "abcdefg" ]; then
    echo "$0: error: mismatch in file test1"
    exit 1
fi
if [ "$(./virt-cat ../tests/guests/fedora.img /etc/test2)" != "" ]; then
    echo "$0: error: mismatch in file test2"
    exit 1
fi
