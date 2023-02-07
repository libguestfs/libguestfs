/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef TESTS_H_
#define TESTS_H_

struct test {
  int (*test_fn) (guestfs_h *g);
  const char *name;
};
extern struct test tests[];
extern size_t nr_tests;

extern int init_none (guestfs_h *g);
extern int init_empty (guestfs_h *g);
extern int init_partition (guestfs_h *g);
extern int init_gpt (guestfs_h *g);
extern int init_basic_fs (guestfs_h *g);
extern int init_basic_fs_on_lvm (guestfs_h *g);
extern int init_iso_fs (guestfs_h *g);
extern int init_scratch_fs (guestfs_h *g);
extern void no_test_warnings (void);
extern int is_string_list (char **ret, size_t n, ...);
extern int is_device_list (char **ret, size_t n, ...);
extern int compare_devices (const char *dev1, const char *dev2);
extern int compare_buffers (const char *b1, size_t s1, const char *b2, size_t s2);
extern int check_file_md5 (const char *ret, const char *filename);
extern const char *get_key (char **hash, const char *key);
extern int check_hash (char **ret, const char *key, const char *expected);
extern int match_re (const char *str, const char *pattern);
extern int using_cross_appliance (void);
extern char *substitute_srcdir (const char *path);
extern void skipped (const char *test_name, const char *fs, ...) __attribute__((format (printf,2,3)));

#endif /* TESTS_H_ */
