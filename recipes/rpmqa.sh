#!/bin/sh -

guestfish -a "$1" --ro -m "$2" command "rpm -qa"
