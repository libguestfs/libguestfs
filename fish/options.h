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

#include <getopt.h>

#include "guestfs-internal-frontend.h"

/* Provided by guestfish or guestmount. */
extern guestfs_h *g;
extern int read_only;
extern int live;
extern int verbose;
extern int inspector;
extern int keys_from_stdin;
extern int echo_keys;
extern const char *libvirt_uri;

/* List of drives added via -a, -d or -N options.  NB: Unused fields
 * in this struct MUST be zeroed, ie. use calloc, not malloc.
 */
struct drv {
  struct drv *next;

  char *device;    /* Device name inside the appliance (eg. /dev/sda).
                    * This is filled in when we add the drives in
                    * add_drives.  Note that guests (-d option) may
                    * have multiple drives, in which case this is the
                    * first drive, and nr_drives is the number of
                    * drives used.
                    */
  int nr_drives;   /* number of drives for this guest */

  enum {
    drv_a,                      /* -a option (without URI) */
    drv_uri,                    /* -a option (with URI) */
    drv_d,                      /* -d option */
#if COMPILING_GUESTFISH
    drv_N,                      /* -N option (guestfish only) */
#endif
  } type;
  union {
    struct {
      char *filename;       /* disk filename */
      const char *format;   /* format (NULL == autodetect) */
    } a;
    struct {
      char *path;           /* disk path */
      char *protocol;       /* protocol (eg. "nbd") */
      char **server;        /* server(s) - can be NULL */
      char *username;       /* username - can be NULL */
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

/* in config.c */
extern void parse_config (void);

/* in inspect.c */
extern void inspect_mount (void);
extern void print_inspect_prompt (void);
/* (low-level inspection functions, used by virt-inspector only) */
extern void inspect_do_decrypt (void);
extern void inspect_mount_root (const char *root);

/* in key.c */
extern char *read_key (const char *param);

/* in options.c */
extern void option_a (const char *arg, const char *format, struct drv **drvsp);
extern char add_drives (struct drv *drv, char next_drive);
extern void mount_mps (struct mp *mp);
extern void free_drives (struct drv *drv);
extern void free_mps (struct mp *mp);
extern void display_long_options (const struct option *) __attribute__((noreturn));

/* in virt.c */
extern int add_libvirt_drives (const char *guest);

#define OPTION_a                                \
  option_a (optarg, format, &drvs)

#define OPTION_c                                \
  libvirt_uri = optarg

#define OPTION_d                                \
  drv = calloc (1, sizeof (struct drv));        \
  if (!drv) {                                   \
    perror ("malloc");                          \
    exit (EXIT_FAILURE);                        \
  }                                             \
  drv->type = drv_d;                            \
  drv->nr_drives = -1;                          \
  drv->d.guest = optarg;                        \
  drv->next = drvs;                             \
  drvs = drv

#define OPTION_i                                \
  inspector = 1

#define OPTION_m                                \
  mp = malloc (sizeof (struct mp));             \
  if (!mp) {                                    \
    perror ("malloc");                          \
    exit (EXIT_FAILURE);                        \
  }                                             \
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
    struct guestfs_version *v = guestfs_version (g);                    \
    printf ("%s %"PRIi64".%"PRIi64".%"PRIi64"%s\n",                     \
            program_name,                                               \
            v->major, v->minor, v->release, v->extra);                  \
    exit (EXIT_SUCCESS);                                                \
  }

#define OPTION_w                                                        \
  if (read_only) {                                                      \
    fprintf (stderr, _("%s: cannot mix --ro and --rw options\n"),       \
             program_name);                                             \
    exit (EXIT_FAILURE);                                                \
  }

#define OPTION_x                                \
  guestfs_set_trace (g, 1)

#endif /* OPTIONS_H */
