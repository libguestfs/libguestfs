/* virt-p2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef P2V_H
#define P2V_H

/* Send various debug information to stderr.  Harmless and useful, so
 * can be left enabled in production builds.
 */
#define DEBUG_STDERR 1

/* Force remote debugging even if user doesn't enable it.  Since
 * remote debugging is mostly free, we might as well enable this even
 * in production.
 */
#define FORCE_REMOTE_DEBUG 1

#include "miniexpect.h"

/* We don't use libguestfs directly here, and we don't link to it
 * either (in fact, we don't want libguestfs on the ISO).  However
 * we include this just so that we can use the convenience macros in
 * guestfs-internal-frontend.h.
 */
#include "guestfs.h"
#include "guestfs-internal-frontend.h"

/* Ensure we don't use libguestfs. */
#define guestfs_h DO_NOT_USE

/* All disks / removable media / network interfaces discovered
 * when the program started.  Do not change these.
 */
extern char **all_disks;
extern char **all_removable;
extern char **all_interfaces;

/* config.c */
struct config {
  int verbose;
  char *server;
  int port;
  char *username;
  char *password;
  int sudo;
  char *guestname;
  int vcpus;
  uint64_t memory;
  int flags;
  char **disks;
  char **removable;
  char **interfaces;
  char **network_map;
  char *output;
  int output_allocation;
  char *output_connection;
  char *output_format;
  char *output_storage;
};

#define FLAG_ACPI 1
#define FLAG_APIC 2
#define FLAG_PAE  4

#define OUTPUT_ALLOCATION_NONE         0
#define OUTPUT_ALLOCATION_SPARSE       1
#define OUTPUT_ALLOCATION_PREALLOCATED 2

extern struct config *new_config (void);
extern struct config *copy_config (struct config *);
extern void free_config (struct config *);

/* kernel-cmdline.c */
extern char **parse_cmdline_string (const char *cmdline);
extern char **parse_proc_cmdline (void);
extern const char *get_cmdline_key (char **cmdline, const char *key);

#define CMDLINE_SOURCE_COMMAND_LINE 1 /* --cmdline */
#define CMDLINE_SOURCE_PROC_CMDLINE 2 /* /proc/cmdline */

/* kernel.c */
extern void kernel_configuration (struct config *, char **cmdline, int cmdline_source);

/* gui.c */
extern void gui_application (struct config *);

/* conversion.c */
extern int start_conversion (struct config *, void (*notify_ui) (int type, const char *data));
#define NOTIFY_LOG_DIR        1  /* location of remote log directory */
#define NOTIFY_REMOTE_MESSAGE 2  /* log message from remote virt-v2v */
#define NOTIFY_STATUS         3  /* stage in conversion process */
extern const char *get_conversion_error (void);
extern void cancel_conversion (void);

/* ssh.c */
extern int test_connection (struct config *);
extern mexp_h *open_data_connection (struct config *, int *local_port, int *remote_port);
extern mexp_h *start_remote_connection (struct config *, const char *remote_dir, const char *libvirt_xml);
extern const char *get_ssh_error (void);

/* utils.c */
extern char *get_if_addr (const char *if_name);
extern char *get_if_vendor (const char *if_name, int truncate);

/* virt-v2v version and features (read from remote). */
extern int v2v_major;
extern int v2v_minor;
extern int v2v_release;

/* input and output drivers (read from remote). */
extern char **input_drivers;
extern char **output_drivers;

/* authors.c */
extern const char *authors[];

/* copying.c */
extern const char *gplv2plus;

#endif /* P2V_H */
