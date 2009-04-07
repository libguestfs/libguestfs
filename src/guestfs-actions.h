/* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED BY 'src/generator.ml'.
 * ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
 *
 * Copyright (C) 2009 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

extern int guestfs_mount (guestfs_h *handle, const char *device, const char *mountpoint);
extern int guestfs_sync (guestfs_h *handle);
extern int guestfs_touch (guestfs_h *handle, const char *path);
extern char *guestfs_cat (guestfs_h *handle, const char *path);
extern char *guestfs_ll (guestfs_h *handle, const char *directory);
extern char **guestfs_ls (guestfs_h *handle, const char *directory);
extern char **guestfs_list_devices (guestfs_h *handle);
extern char **guestfs_list_partitions (guestfs_h *handle);
extern struct guestfs_lvm_pv_list *guestfs_pvs_full (guestfs_h *handle);
extern struct guestfs_lvm_vg_list *guestfs_vgs_full (guestfs_h *handle);
extern struct guestfs_lvm_lv_list *guestfs_lvs_full (guestfs_h *handle);
