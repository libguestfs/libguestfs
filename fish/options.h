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

#ifndef _
#define _(str) dgettext(PACKAGE, (str))
#endif
#ifndef N_
#define N_(str) dgettext(PACKAGE, (str))
#endif

#ifndef STREQ
#define STREQ(a,b) (strcmp((a),(b)) == 0)
#endif
#ifndef STRCASEEQ
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
#endif
#ifndef STRNEQ
#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
#endif
#ifndef STRCASENEQ
#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#endif
#ifndef STREQLEN
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
#endif
#ifndef STRCASEEQLEN
#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
#endif
#ifndef STRNEQLEN
#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
#endif
#ifndef STRCASENEQLEN
#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#endif
#ifndef STRPREFIX
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)
#endif

/* Provided by guestfish or guestmount. */
extern guestfs_h *g;
extern int read_only;
extern int live;
extern int verbose;
extern int inspector;
extern int keys_from_stdin;
extern int echo_keys;
extern const char *libvirt_uri;
extern const char *program_name;

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

  enum { drv_a, drv_d, drv_N } type;
  union {
    struct {
      char *filename;       /* disk filename */
      const char *format;   /* format (NULL == autodetect) */
    } a;
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
extern char add_drives (struct drv *drv, char next_drive);
extern void mount_mps (struct mp *mp);
extern void free_drives (struct drv *drv);
extern void free_mps (struct mp *mp);

/* in virt.c */
extern int add_libvirt_drives (const char *guest);

#define OPTION_a                                \
  if (access (optarg, R_OK) != 0) {             \
    perror (optarg);                            \
    exit (EXIT_FAILURE);                        \
  }                                             \
  drv = calloc (1, sizeof (struct drv));        \
  if (!drv) {                                   \
    perror ("malloc");                          \
    exit (EXIT_FAILURE);                        \
  }                                             \
  drv->type = drv_a;                            \
  drv->nr_drives = -1;                          \
  drv->a.filename = optarg;                     \
  drv->a.format = format;                       \
  drv->next = drvs;                             \
  drvs = drv

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
  mp->options = NULL;                           \
  mp->mountpoint = bad_cast ("/");              \
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
