#!/bin/bash -

export LANG=C
set -e

# Make a copy of the Fedora image so we can write to it then
# discard it.
cp ../tests/guests/fedora.img test.img

# Edit interactively.  We have to simulate this by setting $EDITOR.
# The command will be: echo newline >> /tmp/file
export EDITOR='echo newline >>'
./virt-edit -a test.img /etc/test3
if [ "$(../cat/virt-cat -a test.img /etc/test3)" != "a
b
c
d
e
f
newline" ]; then
    echo "$0: error: mismatch in interactive editing of file /etc/test3"
    exit 1
fi
unset EDITOR

# Edit non-interactively, only if we have 'perl' binary.
if perl --version >/dev/null 2>&1; then
    ./virt-edit -a test.img /etc/test3 -e 's/^[a-f]/$lineno/'
    if [ "$(../cat/virt-cat -a test.img /etc/test3)" != "1
2
3
4
5
6
newline" ]; then
        echo "$0: error: mismatch in non-interactive editing of file /etc/test3"
        exit 1
    fi
fi

# Verify the mode of /etc/test3 is still 0600 and the UID:GID is 10:11.
# See tests/guests/guest-aux/make-fedora-img.pl and RHBZ#788641.
if [ "$(../fish/guestfish -i -a test.img --ro lstat /etc/test3 | grep -E '^(mode|uid|gid):' | sort)" != "gid: 11
mode: 33152
uid: 10" ]; then
    echo "$0: error: editing /etc/test3 did not preserve permissions or ownership"
    exit 1
fi

# Discard test image.
rm test.img
