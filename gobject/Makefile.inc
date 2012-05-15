# libguestfs generated file
# WARNING: THIS FILE IS GENERATED FROM:
#   generator/generator_*.ml
# ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
#
# Copyright (C) 2009-2012 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

guestfs_gobject_headers= \
  include/guestfs-gobject.h \
  include/guestfs-gobject/session.h \
  include/guestfs-gobject/tristate.h \
  include/guestfs-gobject/struct-int_bool.h \
  include/guestfs-gobject/struct-lvm_pv.h \
  include/guestfs-gobject/struct-lvm_vg.h \
  include/guestfs-gobject/struct-lvm_lv.h \
  include/guestfs-gobject/struct-stat.h \
  include/guestfs-gobject/struct-statvfs.h \
  include/guestfs-gobject/struct-dirent.h \
  include/guestfs-gobject/struct-version.h \
  include/guestfs-gobject/struct-xattr.h \
  include/guestfs-gobject/struct-inotify_event.h \
  include/guestfs-gobject/struct-partition.h \
  include/guestfs-gobject/struct-application.h \
  include/guestfs-gobject/struct-isoinfo.h \
  include/guestfs-gobject/struct-mdstat.h \
  include/guestfs-gobject/struct-btrfssubvolume.h \
  include/guestfs-gobject/optargs-test0.h \
  include/guestfs-gobject/optargs-add_drive_opts.h \
  include/guestfs-gobject/optargs-add_domain.h \
  include/guestfs-gobject/optargs-inspect_get_icon.h \
  include/guestfs-gobject/optargs-mount_local.h \
  include/guestfs-gobject/optargs-umount_local.h \
  include/guestfs-gobject/optargs-mkfs_opts.h \
  include/guestfs-gobject/optargs-mount_9p.h \
  include/guestfs-gobject/optargs-ntfsresize_opts.h \
  include/guestfs-gobject/optargs-btrfs_filesystem_resize.h \
  include/guestfs-gobject/optargs-compress_out.h \
  include/guestfs-gobject/optargs-compress_device_out.h \
  include/guestfs-gobject/optargs-copy_device_to_device.h \
  include/guestfs-gobject/optargs-copy_device_to_file.h \
  include/guestfs-gobject/optargs-copy_file_to_device.h \
  include/guestfs-gobject/optargs-copy_file_to_file.h \
  include/guestfs-gobject/optargs-tune2fs.h \
  include/guestfs-gobject/optargs-md_create.h \
  include/guestfs-gobject/optargs-e2fsck.h \
  include/guestfs-gobject/optargs-ntfsfix.h \
  include/guestfs-gobject/optargs-ntfsclone_out.h \
  include/guestfs-gobject/optargs-mkfs_btrfs.h \
  include/guestfs-gobject/optargs-set_e2attrs.h \
  include/guestfs-gobject/optargs-btrfs_fsck.h

guestfs_gobject_sources= \
  src/session.c \
  src/tristate.c \
  src/struct-int_bool.c \
  src/struct-lvm_pv.c \
  src/struct-lvm_vg.c \
  src/struct-lvm_lv.c \
  src/struct-stat.c \
  src/struct-statvfs.c \
  src/struct-dirent.c \
  src/struct-version.c \
  src/struct-xattr.c \
  src/struct-inotify_event.c \
  src/struct-partition.c \
  src/struct-application.c \
  src/struct-isoinfo.c \
  src/struct-mdstat.c \
  src/struct-btrfssubvolume.c \
  src/optargs-test0.c \
  src/optargs-add_drive_opts.c \
  src/optargs-add_domain.c \
  src/optargs-inspect_get_icon.c \
  src/optargs-mount_local.c \
  src/optargs-umount_local.c \
  src/optargs-mkfs_opts.c \
  src/optargs-mount_9p.c \
  src/optargs-ntfsresize_opts.c \
  src/optargs-btrfs_filesystem_resize.c \
  src/optargs-compress_out.c \
  src/optargs-compress_device_out.c \
  src/optargs-copy_device_to_device.c \
  src/optargs-copy_device_to_file.c \
  src/optargs-copy_file_to_device.c \
  src/optargs-copy_file_to_file.c \
  src/optargs-tune2fs.c \
  src/optargs-md_create.c \
  src/optargs-e2fsck.c \
  src/optargs-ntfsfix.c \
  src/optargs-ntfsclone_out.c \
  src/optargs-mkfs_btrfs.c \
  src/optargs-set_e2attrs.c \
  src/optargs-btrfs_fsck.c
