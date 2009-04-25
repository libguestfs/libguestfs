#!/bin/sh -

guestfish -a "$1" -m "$2" vi /grub/grub.conf
