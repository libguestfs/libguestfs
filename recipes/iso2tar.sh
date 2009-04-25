#!/bin/sh -

guestfish -a "$1" -m /dev/sda tgz-out / "$2"
