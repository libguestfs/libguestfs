#!/bin/sh -

guestfish -a "$1" -i edit /boot/grub/grub.conf
