#!/bin/sh -

guestfish -a "$1" --ro -m /dev/sda tgz-out / "$2"
