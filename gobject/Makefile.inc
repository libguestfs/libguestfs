# libguestfs generated file
# WARNING: THIS FILE IS GENERATED FROM THE FOLLOWING FILES:
#          generator/gobject.ml
#          and from the code in the generator/ subdirectory.
# ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
#
# Copyright (C) 2009-2016 Red Hat Inc.
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
  include/guestfs-gobject/struct-application.h \
  include/guestfs-gobject/struct-application2.h \
  include/guestfs-gobject/struct-btrfsbalance.h \
  include/guestfs-gobject/struct-btrfsqgroup.h \
  include/guestfs-gobject/struct-btrfsscrub.h \
  include/guestfs-gobject/struct-btrfssubvolume.h \
  include/guestfs-gobject/struct-dirent.h \
  include/guestfs-gobject/struct-hivex_node.h \
  include/guestfs-gobject/struct-hivex_value.h \
  include/guestfs-gobject/struct-inotify_event.h \
  include/guestfs-gobject/struct-int_bool.h \
  include/guestfs-gobject/struct-isoinfo.h \
  include/guestfs-gobject/struct-lvm_lv.h \
  include/guestfs-gobject/struct-lvm_pv.h \
  include/guestfs-gobject/struct-lvm_vg.h \
  include/guestfs-gobject/struct-mdstat.h \
  include/guestfs-gobject/struct-partition.h \
  include/guestfs-gobject/struct-stat.h \
  include/guestfs-gobject/struct-statns.h \
  include/guestfs-gobject/struct-statvfs.h \
  include/guestfs-gobject/struct-utsname.h \
  include/guestfs-gobject/struct-version.h \
  include/guestfs-gobject/struct-xattr.h \
  include/guestfs-gobject/struct-xfsinfo.h \
  include/guestfs-gobject/optargs-add_domain.h \
  include/guestfs-gobject/optargs-add_drive.h \
  include/guestfs-gobject/optargs-add_drive_scratch.h \
  include/guestfs-gobject/optargs-add_libvirt_dom.h \
  include/guestfs-gobject/optargs-btrfs_filesystem_defragment.h \
  include/guestfs-gobject/optargs-btrfs_filesystem_resize.h \
  include/guestfs-gobject/optargs-btrfs_fsck.h \
  include/guestfs-gobject/optargs-btrfs_image.h \
  include/guestfs-gobject/optargs-btrfs_subvolume_create.h \
  include/guestfs-gobject/optargs-btrfs_subvolume_snapshot.h \
  include/guestfs-gobject/optargs-compress_device_out.h \
  include/guestfs-gobject/optargs-compress_out.h \
  include/guestfs-gobject/optargs-copy_attributes.h \
  include/guestfs-gobject/optargs-copy_device_to_device.h \
  include/guestfs-gobject/optargs-copy_device_to_file.h \
  include/guestfs-gobject/optargs-copy_file_to_device.h \
  include/guestfs-gobject/optargs-copy_file_to_file.h \
  include/guestfs-gobject/optargs-cpio_out.h \
  include/guestfs-gobject/optargs-disk_create.h \
  include/guestfs-gobject/optargs-e2fsck.h \
  include/guestfs-gobject/optargs-fstrim.h \
  include/guestfs-gobject/optargs-glob_expand.h \
  include/guestfs-gobject/optargs-grep.h \
  include/guestfs-gobject/optargs-hivex_open.h \
  include/guestfs-gobject/optargs-inspect_get_icon.h \
  include/guestfs-gobject/optargs-internal_test.h \
  include/guestfs-gobject/optargs-internal_test_63_optargs.h \
  include/guestfs-gobject/optargs-internal_test_only_optargs.h \
  include/guestfs-gobject/optargs-is_blockdev.h \
  include/guestfs-gobject/optargs-is_chardev.h \
  include/guestfs-gobject/optargs-is_dir.h \
  include/guestfs-gobject/optargs-is_fifo.h \
  include/guestfs-gobject/optargs-is_file.h \
  include/guestfs-gobject/optargs-is_socket.h \
  include/guestfs-gobject/optargs-md_create.h \
  include/guestfs-gobject/optargs-mke2fs.h \
  include/guestfs-gobject/optargs-mkfs.h \
  include/guestfs-gobject/optargs-mkfs_btrfs.h \
  include/guestfs-gobject/optargs-mkswap.h \
  include/guestfs-gobject/optargs-mktemp.h \
  include/guestfs-gobject/optargs-mount_local.h \
  include/guestfs-gobject/optargs-ntfsclone_out.h \
  include/guestfs-gobject/optargs-ntfsfix.h \
  include/guestfs-gobject/optargs-ntfsresize.h \
  include/guestfs-gobject/optargs-remount.h \
  include/guestfs-gobject/optargs-rsync.h \
  include/guestfs-gobject/optargs-rsync_in.h \
  include/guestfs-gobject/optargs-rsync_out.h \
  include/guestfs-gobject/optargs-selinux_relabel.h \
  include/guestfs-gobject/optargs-set_e2attrs.h \
  include/guestfs-gobject/optargs-syslinux.h \
  include/guestfs-gobject/optargs-tar_in.h \
  include/guestfs-gobject/optargs-tar_out.h \
  include/guestfs-gobject/optargs-tune2fs.h \
  include/guestfs-gobject/optargs-umount.h \
  include/guestfs-gobject/optargs-umount_local.h \
  include/guestfs-gobject/optargs-xfs_admin.h \
  include/guestfs-gobject/optargs-xfs_growfs.h \
  include/guestfs-gobject/optargs-xfs_repair.h

guestfs_gobject_sources= \
  src/session.c \
  src/tristate.c \
  src/struct-application.c \
  src/struct-application2.c \
  src/struct-btrfsbalance.c \
  src/struct-btrfsqgroup.c \
  src/struct-btrfsscrub.c \
  src/struct-btrfssubvolume.c \
  src/struct-dirent.c \
  src/struct-hivex_node.c \
  src/struct-hivex_value.c \
  src/struct-inotify_event.c \
  src/struct-int_bool.c \
  src/struct-isoinfo.c \
  src/struct-lvm_lv.c \
  src/struct-lvm_pv.c \
  src/struct-lvm_vg.c \
  src/struct-mdstat.c \
  src/struct-partition.c \
  src/struct-stat.c \
  src/struct-statns.c \
  src/struct-statvfs.c \
  src/struct-utsname.c \
  src/struct-version.c \
  src/struct-xattr.c \
  src/struct-xfsinfo.c \
  src/optargs-add_domain.c \
  src/optargs-add_drive.c \
  src/optargs-add_drive_scratch.c \
  src/optargs-add_libvirt_dom.c \
  src/optargs-btrfs_filesystem_defragment.c \
  src/optargs-btrfs_filesystem_resize.c \
  src/optargs-btrfs_fsck.c \
  src/optargs-btrfs_image.c \
  src/optargs-btrfs_subvolume_create.c \
  src/optargs-btrfs_subvolume_snapshot.c \
  src/optargs-compress_device_out.c \
  src/optargs-compress_out.c \
  src/optargs-copy_attributes.c \
  src/optargs-copy_device_to_device.c \
  src/optargs-copy_device_to_file.c \
  src/optargs-copy_file_to_device.c \
  src/optargs-copy_file_to_file.c \
  src/optargs-cpio_out.c \
  src/optargs-disk_create.c \
  src/optargs-e2fsck.c \
  src/optargs-fstrim.c \
  src/optargs-glob_expand.c \
  src/optargs-grep.c \
  src/optargs-hivex_open.c \
  src/optargs-inspect_get_icon.c \
  src/optargs-internal_test.c \
  src/optargs-internal_test_63_optargs.c \
  src/optargs-internal_test_only_optargs.c \
  src/optargs-is_blockdev.c \
  src/optargs-is_chardev.c \
  src/optargs-is_dir.c \
  src/optargs-is_fifo.c \
  src/optargs-is_file.c \
  src/optargs-is_socket.c \
  src/optargs-md_create.c \
  src/optargs-mke2fs.c \
  src/optargs-mkfs.c \
  src/optargs-mkfs_btrfs.c \
  src/optargs-mkswap.c \
  src/optargs-mktemp.c \
  src/optargs-mount_local.c \
  src/optargs-ntfsclone_out.c \
  src/optargs-ntfsfix.c \
  src/optargs-ntfsresize.c \
  src/optargs-remount.c \
  src/optargs-rsync.c \
  src/optargs-rsync_in.c \
  src/optargs-rsync_out.c \
  src/optargs-selinux_relabel.c \
  src/optargs-set_e2attrs.c \
  src/optargs-syslinux.c \
  src/optargs-tar_in.c \
  src/optargs-tar_out.c \
  src/optargs-tune2fs.c \
  src/optargs-umount.c \
  src/optargs-umount_local.c \
  src/optargs-xfs_admin.c \
  src/optargs-xfs_growfs.c \
  src/optargs-xfs_repair.c
