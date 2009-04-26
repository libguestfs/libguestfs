#!/bin/sh -

guestfish -a "$1" --ro -m "$2" tgz-out "$3" "$4"
