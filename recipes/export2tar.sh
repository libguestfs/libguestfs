#!/bin/sh -

guestfish --ro -a "$1" -m "$2" tgz-out "$3" "$4"
