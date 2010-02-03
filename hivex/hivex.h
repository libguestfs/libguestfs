/* hivex - Windows Registry "hive" extraction library.
 * Copyright (C) 2009 Red Hat Inc.
 * Derived from code by Petter Nordahl-Hagen under a compatible license:
 *   Copyright (c) 1997-2007 Petter Nordahl-Hagen.
 * Derived from code by Markus Stephany under a compatible license:
 *   Copyright (c)2000-2004, Markus Stephany.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation;
 * version 2.1 of the License.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * See file LICENSE for the full license.
 */

#ifndef HIVEX_H_
#define HIVEX_H_

#ifdef __cplusplus
extern "C" {
#endif

/* NOTE: This API is documented in the man page hivex(3). */

typedef struct hive_h hive_h;
typedef size_t hive_node_h;
typedef size_t hive_value_h;

enum hive_type {
  /* Just a key without a value. */
  hive_t_none = 0,

  /* A UTF-16 Windows string. */
  hive_t_string = 1,

  /* A UTF-16 Windows string that contains %env% (environment variable
   * substitutions).
   */
  hive_t_expand_string = 2,

  /* A blob of binary. */
  hive_t_binary = 3,

  /* Two ways to encode DWORDs (32 bit words).  The first is little-endian. */
  hive_t_dword = 4,
  hive_t_dword_be = 5,

  /* Symbolic link, we think to another part of the registry tree. */
  hive_t_link = 6,

  /* Multiple UTF-16 Windows strings, each separated by zero byte.  See:
   * http://blogs.msdn.com/oldnewthing/archive/2009/10/08/9904646.aspx
   */
  hive_t_multiple_strings = 7,

  /* These three are unknown. */
  hive_t_resource_list = 8,
  hive_t_full_resource_description = 9,
  hive_t_resource_requirements_list = 10,

  /* A QWORD (64 bit word).  This is stored in the file little-endian. */
  hive_t_qword = 11
};

typedef enum hive_type hive_type;

/* Bitmask of flags passed to hivex_open. */
#define HIVEX_OPEN_VERBOSE      1
#define HIVEX_OPEN_DEBUG        2
#define HIVEX_OPEN_MSGLVL_MASK  (HIVEX_OPEN_VERBOSE|HIVEX_OPEN_DEBUG)
#define HIVEX_OPEN_WRITE        4

extern hive_h *hivex_open (const char *filename, int flags);
extern int hivex_close (hive_h *h);
extern hive_node_h hivex_root (hive_h *h);
extern char *hivex_node_name (hive_h *h, hive_node_h node);
extern hive_node_h *hivex_node_children (hive_h *h, hive_node_h node);
extern hive_node_h hivex_node_get_child (hive_h *h, hive_node_h node, const char *name);
extern hive_node_h hivex_node_parent (hive_h *h, hive_node_h node);
extern hive_value_h *hivex_node_values (hive_h *h, hive_node_h node);
extern hive_value_h hivex_node_get_value (hive_h *h, hive_node_h node, const char *key);
extern char *hivex_value_key (hive_h *h, hive_value_h value);
extern int hivex_value_type (hive_h *h, hive_value_h value, hive_type *t, size_t *len);
extern char *hivex_value_value (hive_h *h, hive_value_h value, hive_type *t, size_t *len);
extern char *hivex_value_string (hive_h *h, hive_value_h value);
extern char **hivex_value_multiple_strings (hive_h *h, hive_value_h value);
extern int32_t hivex_value_dword (hive_h *h, hive_value_h value);
extern int64_t hivex_value_qword (hive_h *h, hive_value_h value);
struct hivex_visitor {
  int (*node_start) (hive_h *, void *opaque, hive_node_h, const char *name);
  int (*node_end) (hive_h *, void *opaque, hive_node_h, const char *name);
  int (*value_string) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *str);
  int (*value_multiple_strings) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, char **argv);
  int (*value_string_invalid_utf16) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *str);
  int (*value_dword) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, int32_t);
  int (*value_qword) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, int64_t);
  int (*value_binary) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);
  int (*value_none) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);
  int (*value_other) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);
  int (*value_any) (hive_h *, void *opaque, hive_node_h, hive_value_h, hive_type t, size_t len, const char *key, const char *value);
};

#define HIVEX_VISIT_SKIP_BAD 1

extern int hivex_visit (hive_h *h, const struct hivex_visitor *visitor, size_t len, void *opaque, int flags);
extern int hivex_visit_node (hive_h *h, hive_node_h node, const struct hivex_visitor *visitor, size_t len, void *opaque, int flags);

extern int hivex_commit (hive_h *h, const char *filename, int flags);
extern hive_node_h hivex_node_add_child (hive_h *h, hive_node_h parent, const char *name);
extern int hivex_node_delete_child (hive_h *h, hive_node_h node);

struct hive_set_value {
  char *key;
  hive_type t;
  size_t len;
  char *value;
};
typedef struct hive_set_value hive_set_value;

extern int hivex_node_set_values (hive_h *h, hive_node_h node, size_t nr_values, const hive_set_value *values, int flags);

#ifdef __cplusplus
}
#endif

#endif /* HIVEX_H_ */
