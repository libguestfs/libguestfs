/* libguestfs - guestfish and guestmount shared option parsing
 * Copyright (C) 2010-2012 Red Hat Inc.
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

#ifndef OPTIONS_H
#define OPTIONS_H

#include <config.h>

#include <stdbool.h>

#include "guestfs-utils.h"

/* Provided by guestfish or guestmount. */
extern guestfs_h *g;
extern int read_only;
extern int live;
extern int verbose;
extern int inspector;
extern int keys_from_stdin;
extern int echo_keys;
extern const char *libvirt_uri;
extern int in_guestfish;
extern int in_virt_rescue;

/* List of drives added via -a, -d or -N options.  NB: Unused fields
 * in this struct MUST be zeroed, ie. use calloc, not malloc.
 */
struct drv {
  struct drv *next;

  /* Drive index.  This is filled in by add_drives(). */
  size_t drive_index;

  /* Number of drives represented by this 'drv' struct.  For -d this
   * can be != 1 because a guest can have more than one disk.  For
   * others it is always 1.  This is filled in by add_drives().
   */
  size_t nr_drives;

  enum {
    drv_a,                      /* -a option (without URI) */
    drv_uri,                    /* -a option (with URI) */
    drv_d,                      /* -d option */
    drv_N,                      /* -N option (guestfish only) */
    drv_scratch,                /* --scratch option (virt-rescue only) */
  } type;
  union {
    struct {
      char *filename;       /* disk filename */
      const char *format;   /* format (NULL == autodetect) */
      const char *cachemode;/* cachemode (NULL == default) */
      const char *discard;  /* discard (NULL == disable) */
    } a;
    struct {
      char *path;           /* disk path */
      char *protocol;       /* protocol (eg. "nbd") */
      char **server;        /* server(s) - can be NULL */
      char *username;       /* username - can be NULL */
      char *password;       /* password - can be NULL */
      const char *format;   /* format (NULL == autodetect) */
      const char *orig_uri; /* original URI (for error messages etc.) */
    } uri;
    struct {
      char *guest;          /* guest name */
    } d;
    struct {
      char *filename;       /* disk filename (testX.img) */
      void *data;           /* prepared type */
      void (*data_free)(void*); /* function to free 'data' */
    } N;
    struct {
      int64_t size;         /* size of the disk in bytes */
    } scratch;
  };

  /* Opaque pointer.  Not used by the options-parsing code, and so
   * available for the program to use for any purpose.
   */
  void *opaque;
};

struct mp {
  struct mp *next;
  char *device;
  char *mountpoint;
  char *options;
  char *fstype;
};

/* A key in the key store. */
struct key_store_key {
  /* An ID for the device this key refers to.  It can be either the libguestfs
   * device name, or the UUID.
   *
   * There may be multiple matching devices in the list.
   */
  char *id;

  enum {
    key_string,             /* key specified as string */
    key_file,               /* key stored in a file */
  } type;
  union {
    struct {
      char *s;              /* string of the key */
    } string;
    struct {
      char *name;           /* filename with the key */
    } file;
  };
};

/* Container for keys, usually collected via the '--key' command line option
 * in tools.
 */
struct key_store {
  struct key_store_key *keys;
  size_t nr_keys;
};

/* in config.c */
extern void parse_config (void);

/* in decrypt.c */
extern void inspect_do_decrypt (guestfs_h *g, struct key_store *ks);

/* in domain.c */
extern int add_libvirt_drives (guestfs_h *g, const char *guest);

/* in inspect.c */
extern void inspect_mount_handle (guestfs_h *g, struct key_store *ks);
extern void inspect_mount_root (guestfs_h *g, const char *root);
#define inspect_mount() inspect_mount_handle (g, ks)
extern void print_inspect_prompt (void);

/* in key.c */
extern char *read_key (const char *param);
extern char **get_keys (struct key_store *ks, const char *device, const char *uuid);
extern struct key_store *key_store_add_from_selector (struct key_store *ks, const char *selector);
extern struct key_store *key_store_import_key (struct key_store *ks, const struct key_store_key *key);
extern void free_key_store (struct key_store *ks);

/* in options.c */
extern void option_a (const char *arg, const char *format, struct drv **drvsp);
extern void option_d (const char *arg, struct drv **drvsp);
extern char add_drives_handle (guestfs_h *g, struct drv *drv, size_t drive_index);
#define add_drives(drv) add_drives_handle (g, drv, 0)
extern void mount_mps (struct mp *mp);
extern void free_drives (struct drv *drv);
extern void free_mps (struct mp *mp);

#define OPTION_a                                \
  do {                                          \
  option_a (optarg, format, &drvs);             \
  format_consumed = true;                       \
  } while (0)

#define OPTION_A                                \
  do {                                          \
    option_a (optarg, format, &drvs2);          \
    format_consumed = true;                     \
  } while (0)

#define OPTION_c                                \
  libvirt_uri = optarg

#define OPTION_d                                \
  option_d (optarg, &drvs)

#define OPTION_D                                \
  option_d (optarg, &drvs2)

#define OPTION_format                           \
  do {                                          \
    if (!optarg || STREQ (optarg, ""))          \
      format = NULL;                            \
    else                                        \
      format = optarg;                          \
    format_consumed = false;                    \
  } while (0)

#define OPTION_i                                \
  inspector = 1

#define OPTION_m                                \
  mp = malloc (sizeof (struct mp));             \
  if (!mp)                                      \
    error (EXIT_FAILURE, errno, "malloc");      \
  mp->fstype = NULL;                            \
  mp->options = NULL;                           \
  mp->mountpoint = (char *) "/";                \
  p = strchr (optarg, ':');                     \
  if (p) {                                      \
    *p = '\0';                                  \
    p++;                                        \
    mp->mountpoint = p;                         \
    p = strchr (p, ':');                        \
    if (p) {                                    \
      *p = '\0';                                \
      p++;                                      \
      mp->options = p;                          \
      p = strchr (p, ':');                      \
      if (p) {                                  \
        *p = '\0';                              \
        p++;                                    \
        mp->fstype = p;                         \
      }                                         \
    }                                           \
  }                                             \
  mp->device = optarg;                          \
  mp->next = mps;                               \
  mps = mp

#define OPTION_n                                \
  guestfs_set_autosync (g, 0)

#define OPTION_r                                \
  read_only = 1

#define OPTION_v                                \
  verbose++;                                    \
  guestfs_set_verbose (g, verbose)

#define OPTION_V                                                        \
  {                                                                     \
    printf ("%s %s\n",                                                  \
            getprogname (),                                             \
            PACKAGE_VERSION_FULL);                                      \
    exit (EXIT_SUCCESS);                                                \
  }

#define OPTION_w                                                        \
  if (read_only) {                                                      \
    fprintf (stderr, _("%s: cannot mix --ro and --rw options\n"),       \
             getprogname ());                                           \
    exit (EXIT_FAILURE);                                                \
  }

#define OPTION_x                                \
  guestfs_set_trace (g, 1)

#define OPTION_key                                                      \
  ks = key_store_add_from_selector (ks, optarg)

#define CHECK_OPTION_format_consumed                                    \
  do {                                                                  \
    if (!format_consumed) {                                             \
      fprintf (stderr,                                                  \
               _("%s: --format parameter must appear before -a parameter\n"), \
               getprogname ());                                         \
      exit (EXIT_FAILURE);                                              \
    }                                                                   \
  } while (0)

#endif /* OPTIONS_H */
