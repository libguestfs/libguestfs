/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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

/* Drives added are stored in an array in the handle.  Code here
 * manages that array and the individual 'struct drive' data.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <assert.h>
#include <sys/types.h>

#include <pcre.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Helper struct to hold all the data needed when creating a new
 * drive.
 */
struct drive_create_data {
  enum drive_protocol protocol;
  struct drive_server *servers;
  size_t nr_servers;
  const char *exportname;           /* File name or path to the resource. */
  const char *username;
  const char *secret;
  bool readonly;
  const char *format;
  const char *iface;
  const char *name;
  const char *disk_label;
  const char *cachemode;
  enum discard discard;
  bool copyonread;
};

/* Compile all the regular expressions once when the shared library is
 * loaded.  PCRE is thread safe so we're supposedly OK here if
 * multiple threads call into the libguestfs API functions below
 * simultaneously.
 */
static pcre *re_hostname_port;

static void compile_regexps (void) __attribute__((constructor));
static void free_regexps (void) __attribute__((destructor));

static void
compile_regexps (void)
{
  const char *err;
  int offset;

#define COMPILE(re,pattern,options)                                     \
  do {                                                                  \
    re = pcre_compile ((pattern), (options), &err, &offset, NULL);      \
    if (re == NULL) {                                                   \
      ignore_value (write (2, err, strlen (err)));                      \
      abort ();                                                         \
    }                                                                   \
  } while (0)

  COMPILE (re_hostname_port, "(.*):(\\d+)$", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_hostname_port);
}

static void free_drive_struct (struct drive *drv);
static void free_drive_source (struct drive_source *src);

/* For readonly drives, create an overlay to protect the original
 * drive content.  Note we never need to clean up these overlays since
 * they are created in the temporary directory and deleted when the
 * handle is closed.
 */
static int
create_overlay (guestfs_h *g, struct drive *drv)
{
  char *overlay;

  assert (g->backend_ops != NULL);

  if (g->backend_ops->create_cow_overlay == NULL) {
    error (g, _("this backend does not support adding read-only drives"));
    return -1;
  }

  debug (g, "creating COW overlay to protect original drive content");
  overlay = g->backend_ops->create_cow_overlay (g, g->backend_data, drv);
  if (overlay == NULL)
    return -1;

  free (drv->overlay);
  drv->overlay = overlay;

  return 0;
}

/* Create and free the 'drive' struct. */
static struct drive *
create_drive_file (guestfs_h *g,
                   const struct drive_create_data *data)
{
  struct drive *drv = safe_calloc (g, 1, sizeof *drv);

  drv->src.protocol = drive_protocol_file;
  drv->src.u.path = safe_strdup (g, data->exportname);
  drv->src.format = data->format ? safe_strdup (g, data->format) : NULL;

  drv->readonly = data->readonly;
  drv->iface = data->iface ? safe_strdup (g, data->iface) : NULL;
  drv->name = data->name ? safe_strdup (g, data->name) : NULL;
  drv->disk_label = data->disk_label ? safe_strdup (g, data->disk_label) : NULL;
  drv->cachemode = data->cachemode ? safe_strdup (g, data->cachemode) : NULL;
  drv->discard = data->discard;
  drv->copyonread = data->copyonread;

  if (data->readonly) {
    if (create_overlay (g, drv) == -1) {
      /* Don't double-free the servers in free_drive_struct, since
       * they are owned by the caller along this error path.
       */
      drv->src.servers = NULL; drv->src.nr_servers = 0;
      free_drive_struct (drv);
      return NULL;
    }
  }

  return drv;
}

static struct drive *
create_drive_non_file (guestfs_h *g,
                       const struct drive_create_data *data)
{
  struct drive *drv = safe_calloc (g, 1, sizeof *drv);

  drv->src.protocol = data->protocol;
  drv->src.servers = data->servers;
  drv->src.nr_servers = data->nr_servers;
  drv->src.u.exportname = safe_strdup (g, data->exportname);
  drv->src.username = data->username ? safe_strdup (g, data->username) : NULL;
  drv->src.secret = data->secret ? safe_strdup (g, data->secret) : NULL;
  drv->src.format = data->format ? safe_strdup (g, data->format) : NULL;

  drv->readonly = data->readonly;
  drv->iface = data->iface ? safe_strdup (g, data->iface) : NULL;
  drv->name = data->name ? safe_strdup (g, data->name) : NULL;
  drv->disk_label = data->disk_label ? safe_strdup (g, data->disk_label) : NULL;
  drv->cachemode = data->cachemode ? safe_strdup (g, data->cachemode) : NULL;
  drv->discard = data->discard;
  drv->copyonread = data->copyonread;

  if (data->readonly) {
    if (create_overlay (g, drv) == -1) {
      /* Don't double-free the servers in free_drive_struct, since
       * they are owned by the caller along this error path.
       */
      drv->src.servers = NULL; drv->src.nr_servers = 0;
      free_drive_struct (drv);
      return NULL;
    }
  }

  return drv;
}

#if 0 /* DISABLED IN RHEL 7 */
static struct drive *
create_drive_curl (guestfs_h *g,
                   const struct drive_create_data *data)
{
  if (data->nr_servers != 1) {
    error (g, _("curl: you must specify exactly one server"));
    return NULL;
  }

  if (data->servers[0].transport != drive_transport_none &&
      data->servers[0].transport != drive_transport_tcp) {
    error (g, _("curl: only tcp transport is supported"));
    return NULL;
  }

  if (STREQ (data->exportname, "")) {
    error (g, _("curl: pathname should not be an empty string"));
    return NULL;
  }

  if (data->exportname[0] != '/') {
    error (g, _("curl: pathname must begin with a '/'"));
    return NULL;
  }

  return create_drive_non_file (g, data);
}

static struct drive *
create_drive_gluster (guestfs_h *g,
                      const struct drive_create_data *data)
{
  if (data->username != NULL) {
    error (g, _("gluster: you cannot specify a username with this protocol"));
    return NULL;
  }
  if (data->secret != NULL) {
    error (g, _("gluster: you cannot specify a secret with this protocol"));
    return NULL;
  }

  if (data->nr_servers != 1) {
    error (g, _("gluster: you must specify exactly one server"));
    return NULL;
  }

  if (STREQ (data->exportname, "")) {
    error (g, _("gluster: volume name parameter should not be an empty string"));
    return NULL;
  }

  if (data->exportname[0] == '/') {
    error (g, _("gluster: volume/image must not begin with a '/'"));
    return NULL;
  }

  return create_drive_non_file (g, data);
}
#endif /* DISABLED IN RHEL 7 */

static int
nbd_port (void)
{
  struct servent *servent;

  servent = getservbyname ("nbd", "tcp");
  if (servent)
    return ntohs (servent->s_port);
  else
    return 10809;
}

static struct drive *
create_drive_nbd (guestfs_h *g,
                  const struct drive_create_data *data)
{
  if (data->username != NULL) {
    error (g, _("nbd: you cannot specify a username with this protocol"));
    return NULL;
  }
  if (data->secret != NULL) {
    error (g, _("nbd: you cannot specify a secret with this protocol"));
    return NULL;
  }

  if (data->nr_servers != 1) {
    error (g, _("nbd: you must specify exactly one server"));
    return NULL;
  }

  if (data->servers[0].port == 0)
    data->servers[0].port = nbd_port ();

  return create_drive_non_file (g, data);
}

static struct drive *
create_drive_rbd (guestfs_h *g,
                  const struct drive_create_data *data)
{
  size_t i;

  for (i = 0; i < data->nr_servers; ++i) {
    if (data->servers[i].transport != drive_transport_none &&
        data->servers[i].transport != drive_transport_tcp) {
      error (g, _("rbd: only tcp transport is supported"));
      return NULL;
    }
    if (data->servers[i].port == 0) {
      error (g, _("rbd: port number must be specified"));
      return NULL;
    }
  }

  if (STREQ (data->exportname, "")) {
    error (g, _("rbd: image name parameter should not be an empty string"));
    return NULL;
  }

  if (data->exportname[0] == '/') {
    error (g, _("rbd: image name must not begin with a '/'"));
    return NULL;
  }

  return create_drive_non_file (g, data);
}

#if 0 /* DISABLED IN RHEL 7 */
static struct drive *
create_drive_sheepdog (guestfs_h *g,
                       const struct drive_create_data *data)
{
  size_t i;

  if (data->username != NULL) {
    error (g, _("sheepdog: you cannot specify a username with this protocol"));
    return NULL;
  }
  if (data->secret != NULL) {
    error (g, _("sheepdog: you cannot specify a secret with this protocol"));
    return NULL;
  }

  for (i = 0; i < data->nr_servers; ++i) {
    if (data->servers[i].transport != drive_transport_none &&
        data->servers[i].transport != drive_transport_tcp) {
      error (g, _("sheepdog: only tcp transport is supported"));
      return NULL;
    }
    if (data->servers[i].port == 0) {
      error (g, _("sheepdog: port number must be specified"));
      return NULL;
    }
  }

  if (STREQ (data->exportname, "")) {
    error (g, _("sheepdog: volume parameter should not be an empty string"));
    return NULL;
  }

  if (data->exportname[0] == '/') {
    error (g, _("sheepdog: volume parameter must not begin with a '/'"));
    return NULL;
  }

  return create_drive_non_file (g, data);
}

static struct drive *
create_drive_ssh (guestfs_h *g,
                  const struct drive_create_data *data)
{
  if (data->nr_servers != 1) {
    error (g, _("ssh: you must specify exactly one server"));
    return NULL;
  }

  if (data->servers[0].transport != drive_transport_none &&
      data->servers[0].transport != drive_transport_tcp) {
    error (g, _("ssh: only tcp transport is supported"));
    return NULL;
  }

  if (STREQ (data->exportname, "")) {
    error (g, _("ssh: pathname should not be an empty string"));
    return NULL;
  }

  if (data->exportname[0] != '/') {
    error (g, _("ssh: pathname must begin with a '/'"));
    return NULL;
  }

  if (data->username && STREQ (data->username, "")) {
    error (g, _("ssh: username should not be an empty string"));
    return NULL;
  }

  return create_drive_non_file (g, data);
}

static struct drive *
create_drive_iscsi (guestfs_h *g,
                    const struct drive_create_data *data)
{
  if (data->username != NULL) {
    error (g, _("iscsi: you cannot specify a username with this protocol"));
    return NULL;
  }

  if (data->secret != NULL) {
    error (g, _("iscsi: you cannot specify a secret with this protocol"));
    return NULL;
  }

  if (data->nr_servers != 1) {
    error (g, _("iscsi: you must specify exactly one server"));
    return NULL;
  }

  if (data->servers[0].transport != drive_transport_none &&
      data->servers[0].transport != drive_transport_tcp) {
    error (g, _("iscsi: only tcp transport is supported"));
    return NULL;
  }

  if (STREQ (data->exportname, "")) {
    error (g, _("iscsi: target name should not be an empty string"));
    return NULL;
  }

  if (data->exportname[0] == '/') {
    error (g, _("iscsi: target string must not begin with a '/'"));
    return NULL;
  }

  return create_drive_non_file (g, data);
}
#endif /* DISABLED IN RHEL 7 */

/* Traditionally you have been able to use /dev/null as a filename, as
 * many times as you like.  Ancient KVM (RHEL 5) cannot handle adding
 * /dev/null readonly.  qemu 1.2 + virtio-scsi segfaults when you use
 * any zero-sized file including /dev/null.  Therefore, we replace
 * /dev/null with a non-zero sized temporary file.  This shouldn't
 * make any difference since users are not supposed to try and access
 * a null drive.
 */
static struct drive *
create_drive_dev_null (guestfs_h *g,
                       struct drive_create_data *data)
{
  CLEANUP_FREE char *tmpfile = NULL;

  if (data->format && STRNEQ (data->format, "raw")) {
    error (g, _("for device '/dev/null', format must be 'raw'"));
    return NULL;
  }

  if (guestfs_int_lazy_make_tmpdir (g) == -1)
    return NULL;

  /* Because we create a special file, there is no point forcing qemu
   * to create an overlay as well.  Save time by setting readonly = false.
   */
  data->readonly = false;

  tmpfile = safe_asprintf (g, "%s/devnull%d", g->tmpdir, ++g->unique);

  if (guestfs_disk_create (g, tmpfile, "raw", 4096, -1) == -1)
    return NULL;

  data->exportname = tmpfile;
  data->discard = discard_disable;
  data->copyonread = false;

  return create_drive_file (g, data);
}

static struct drive *
create_drive_dummy (guestfs_h *g)
{
  /* A special drive struct that is used as a dummy slot for the appliance. */
  struct drive_create_data data = { 0, };
  data.exportname = "";
  return create_drive_file (g, &data);
}

static void
free_drive_servers (struct drive_server *servers, size_t nr_servers)
{
  if (servers) {
    size_t i;

    for (i = 0; i < nr_servers; ++i)
      free (servers[i].u.hostname);
    free (servers);
  }
}

static void
free_drive_struct (struct drive *drv)
{
  free_drive_source (&drv->src);
  free (drv->overlay);
  free (drv->iface);
  free (drv->name);
  free (drv->disk_label);
  free (drv->cachemode);

  free (drv);
}

const char *
guestfs_int_drive_protocol_to_string (enum drive_protocol protocol)
{
  switch (protocol) {
  case drive_protocol_file: return "file";
  case drive_protocol_ftp: return "ftp";
  case drive_protocol_ftps: return "ftps";
  case drive_protocol_gluster: return "gluster";
  case drive_protocol_http: return "http";
  case drive_protocol_https: return "https";
  case drive_protocol_iscsi: return "iscsi";
  case drive_protocol_nbd: return "nbd";
  case drive_protocol_rbd: return "rbd";
  case drive_protocol_sheepdog: return "sheepdog";
  case drive_protocol_ssh: return "ssh";
  case drive_protocol_tftp: return "tftp";
  }
  abort ();
}

/* Convert a struct drive to a string for debugging.  The caller
 * must free this string.
 */
static char *
drive_to_string (guestfs_h *g, const struct drive *drv)
{
  return safe_asprintf
    (g, "%s%s%s%s protocol=%s%s%s%s%s%s%s%s%s%s%s",
     drv->src.u.path,
     drv->readonly ? " readonly" : "",
     drv->src.format ? " format=" : "",
     drv->src.format ? : "",
     guestfs_int_drive_protocol_to_string (drv->src.protocol),
     drv->iface ? " iface=" : "",
     drv->iface ? : "",
     drv->name ? " name=" : "",
     drv->name ? : "",
     drv->disk_label ? " label=" : "",
     drv->disk_label ? : "",
     drv->cachemode ? " cache=" : "",
     drv->cachemode ? : "",
     drv->discard == discard_disable ? "" :
     drv->discard == discard_enable ? " discard=enable" : " discard=besteffort",
     drv->copyonread ? " copyonread" : "");
}

/* Add struct drive to the g->drives vector at the given index. */
static void
add_drive_to_handle_at (guestfs_h *g, struct drive *d, size_t drv_index)
{
  if (drv_index >= g->nr_drives) {
    g->drives = safe_realloc (g, g->drives,
                              sizeof (struct drive *) * (drv_index + 1));
    while (g->nr_drives <= drv_index) {
      g->drives[g->nr_drives] = NULL;
      g->nr_drives++;
    }
  }

  assert (g->drives[drv_index] == NULL);

  g->drives[drv_index] = d;
}

/* Add struct drive to the end of the g->drives vector in the handle. */
static void
add_drive_to_handle (guestfs_h *g, struct drive *d)
{
  add_drive_to_handle_at (g, d, g->nr_drives);
}

/* Called during launch to add a dummy slot to g->drives. */
void
guestfs_int_add_dummy_appliance_drive (guestfs_h *g)
{
  struct drive *drv;

  drv = create_drive_dummy (g);
  add_drive_to_handle (g, drv);
}

/* Free up all the drives in the handle. */
void
guestfs_int_free_drives (guestfs_h *g)
{
  struct drive *drv;
  size_t i;

  ITER_DRIVES (g, i, drv) {
    free_drive_struct (drv);
  }

  free (g->drives);

  g->drives = NULL;
  g->nr_drives = 0;
}

/* Check string parameter matches ^[-_[:alnum:]]+$ (in C locale). */
static int
valid_format_iface (const char *str)
{
  size_t len = strlen (str);

  if (len == 0)
    return 0;

  while (len > 0) {
    char c = *str++;
    len--;
    if (c != '-' && c != '_' && !c_isalnum (c))
      return 0;
  }
  return 1;
}

/* Check the disk label is reasonable.  It can't contain certain
 * characters, eg. '/', ','.  However be stricter here and ensure it's
 * just alphabetic and <= 20 characters in length.
 */
static int
valid_disk_label (const char *str)
{
  size_t len = strlen (str);

  if (len == 0 || len > 20)
    return 0;

  while (len > 0) {
    char c = *str++;
    len--;
    if (!c_isalpha (c))
      return 0;
  }
  return 1;
}

/* Check the server hostname is reasonable. */
static int
valid_hostname (const char *str)
{
  size_t len = strlen (str);

  if (len == 0 || len > 255)
    return 0;

  while (len > 0) {
    char c = *str++;
    len--;
    if (!c_isalnum (c) &&
        c != '-' && c != '.' && c != ':' && c != '[' && c != ']')
      return 0;
  }
  return 1;
}

/* Check the port number is reasonable. */
static int
valid_port (int port)
{
  if (port <= 0 || port > 65535)
    return 0;
  return 1;
}

static int
parse_one_server (guestfs_h *g, const char *server, struct drive_server *ret)
{
  char *hostname;
  char *port_str;
  int port;

  /* Note! Do not set any string field in *ret until you know the
   * function will return successfully.  Otherwise there can be a
   * double-free in parse_servers -> free_drive_servers below.
   */

  ret->transport = drive_transport_none;

  if (STRPREFIX (server, "tcp:")) {
    /* Explicit tcp: prefix means to skip the unix test. */
    server += 4;
    ret->transport = drive_transport_tcp;
    goto skip_unix;
  }

  if (STRPREFIX (server, "unix:")) {
    if (strlen (server) == 5) {
      error (g, _("missing Unix domain socket path"));
      return -1;
    }
    ret->transport = drive_transport_unix;
    ret->u.socket = safe_strdup (g, server+5);
    ret->port = 0;
    return 0;
  }
 skip_unix:

  if (match2 (g, server, re_hostname_port, &hostname, &port_str)) {
    if (sscanf (port_str, "%d", &port) != 1 || !valid_port (port)) {
      error (g, _("invalid port number '%s'"), port_str);
      free (hostname);
      free (port_str);
      return -1;
    }
    free (port_str);
    if (!valid_hostname (hostname)) {
      error (g, _("invalid hostname '%s'"), hostname);
      free (hostname);
      return -1;
    }
    ret->u.hostname = hostname;
    ret->port = port;
    return 0;
  }

  /* Doesn't match anything above, so assume it's a bare hostname. */
  if (!valid_hostname (server)) {
    error (g, _("invalid hostname or server string '%s'"), server);
    return -1;
  }

  ret->u.hostname = safe_strdup (g, server);
  ret->port = 0;
  return 0;
}

static ssize_t
parse_servers (guestfs_h *g, char *const *strs,
               struct drive_server **servers_rtn)
{
  size_t i;
  size_t n = guestfs_int_count_strings (strs);
  struct drive_server *servers;

  if (n == 0) {
    *servers_rtn = NULL;
    return 0;
  }

  /* Must use calloc here to avoid freeing garbage along the error
   * path below.
   */
  servers = safe_calloc (g, n, sizeof (struct drive_server));

  for (i = 0; i < n; ++i) {
    if (parse_one_server (g, strs[i], &servers[i]) == -1) {
      free_drive_servers (servers, i);
      return -1;
    }
  }

  *servers_rtn = servers;
  return n;
}

int
guestfs_impl_add_drive_opts (guestfs_h *g, const char *filename,
                         const struct guestfs_add_drive_opts_argv *optargs)
{
  struct drive_create_data data;
  const char *protocol;
  struct drive *drv;
  size_t i, drv_index;

  data.nr_servers = 0;
  data.servers = NULL;
  data.exportname = filename;

  data.readonly = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK
    ? optargs->readonly : false;
  data.format = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK
    ? optargs->format : NULL;
  data.iface = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
    ? optargs->iface : NULL;
  data.name = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_NAME_BITMASK
    ? optargs->name : NULL;
  data.disk_label = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_LABEL_BITMASK
    ? optargs->label : NULL;
  protocol = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_PROTOCOL_BITMASK
    ? optargs->protocol : "file";
  if (optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_SERVER_BITMASK) {
    ssize_t r = parse_servers (g, optargs->server, &data.servers);
    if (r == -1)
      return -1;
    data.nr_servers = r;
  }
  data.username = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_USERNAME_BITMASK
    ? optargs->username : NULL;
  data.secret = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_SECRET_BITMASK
    ? optargs->secret : NULL;
  data.cachemode = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_CACHEMODE_BITMASK
    ? optargs->cachemode : NULL;

  if (optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_DISCARD_BITMASK) {
    if (STREQ (optargs->discard, "disable"))
      data.discard = discard_disable;
    else if (STREQ (optargs->discard, "enable"))
      data.discard = discard_enable;
    else if (STREQ (optargs->discard, "besteffort"))
      data.discard = discard_besteffort;
    else {
      error (g, _("discard parameter must be 'disable', 'enable' or 'besteffort'"));
      free_drive_servers (data.servers, data.nr_servers);
      return -1;
    }
  }
  else
    data.discard = discard_disable;

  data.copyonread =
    optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_COPYONREAD_BITMASK
    ? optargs->copyonread : false;

  if (data.readonly && data.discard == discard_enable) {
    error (g, _("discard support cannot be enabled on read-only drives"));
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }

  if (data.format && !valid_format_iface (data.format)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "format");
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }
  if (data.iface && !valid_format_iface (data.iface)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "iface");
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }
  if (data.disk_label && !valid_disk_label (data.disk_label)) {
    error (g, _("label parameter is empty, too long, or contains disallowed characters"));
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }
  if (data.cachemode &&
      !(STREQ (data.cachemode, "writeback") || STREQ (data.cachemode, "unsafe"))) {
    error (g, _("cachemode parameter must be 'writeback' (default) or 'unsafe'"));
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }

  if (STREQ (protocol, "file")) {
    if (data.servers != NULL) {
      error (g, _("you cannot specify a server with file-backed disks"));
      free_drive_servers (data.servers, data.nr_servers);
      return -1;
    }
    if (data.username != NULL) {
      error (g, _("you cannot specify a username with file-backed disks"));
      return -1;
    }
    if (data.secret != NULL) {
      error (g, _("you cannot specify a secret with file-backed disks"));
      return -1;
    }

    if (STREQ (filename, "/dev/null"))
      drv = create_drive_dev_null (g, &data);
    else {
      /* We have to check for the existence of the file since that's
       * required by the API.
       */
      if (access (filename, R_OK) == -1) {
        perrorf (g, "%s", filename);
        return -1;
      }

      drv = create_drive_file (g, &data);
    }
  }
#if 0 /* DISABLED IN RHEL 7 */
  else if (STREQ (protocol, "ftp")) {
    data.protocol = drive_protocol_ftp;
    drv = create_drive_curl (g, &data);
  }
  else if (STREQ (protocol, "ftps")) {
    data.protocol = drive_protocol_ftps;
    drv = create_drive_curl (g, &data);
  }
  else if (STREQ (protocol, "gluster")) {
    data.protocol = drive_protocol_gluster;
    drv = create_drive_gluster (g, &data);
  }
  else if (STREQ (protocol, "http")) {
    data.protocol = drive_protocol_http;
    drv = create_drive_curl (g, &data);
  }
  else if (STREQ (protocol, "https")) {
    data.protocol = drive_protocol_https;
    drv = create_drive_curl (g, &data);
  }
  else if (STREQ (protocol, "iscsi")) {
    data.protocol = drive_protocol_iscsi;
    drv = create_drive_iscsi (g, &data);
  }
#endif /* DISABLED IN RHEL 7 */
  else if (STREQ (protocol, "nbd")) {
    data.protocol = drive_protocol_nbd;
    drv = create_drive_nbd (g, &data);
  }
  else if (STREQ (protocol, "rbd")) {
    data.protocol = drive_protocol_rbd;
    drv = create_drive_rbd (g, &data);
  }
#if 0 /* DISABLED IN RHEL 7 */
  else if (STREQ (protocol, "sheepdog")) {
    data.protocol = drive_protocol_sheepdog;
    drv = create_drive_sheepdog (g, &data);
  }
  else if (STREQ (protocol, "ssh")) {
    data.protocol = drive_protocol_ssh;
    drv = create_drive_ssh (g, &data);
  }
  else if (STREQ (protocol, "tftp")) {
    data.protocol = drive_protocol_tftp;
    drv = create_drive_curl (g, &data);
  }
#endif /* DISABLED IN RHEL 7 */
  else {
    error (g, _("unknown protocol '%s'"), protocol);
    drv = NULL; /*FALLTHROUGH*/
  }

  if (drv == NULL) {
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }

  /* Add the drive. */
  if (g->state == CONFIG) {
    /* Not hotplugging, so just add it to the handle. */
    add_drive_to_handle (g, drv); /* drv is now owned by the handle */
    return 0;
  }

  /* ... else, hotplugging case. */
  if (!g->backend_ops->hot_add_drive) {
    error (g, _("the current backend does not support hotplugging drives"));
    free_drive_struct (drv);
    return -1;
  }

  if (!drv->disk_label) {
    error (g, _("'label' is required when hotplugging drives"));
    free_drive_struct (drv);
    return -1;
  }

  /* Get the first free index, or add it at the end. */
  drv_index = g->nr_drives;
  for (i = 0; i < g->nr_drives; ++i)
    if (g->drives[i] == NULL)
      drv_index = i;

  /* Hot-add the drive. */
  if (g->backend_ops->hot_add_drive (g, g->backend_data,
                                     drv, drv_index) == -1) {
    free_drive_struct (drv);
    return -1;
  }

  add_drive_to_handle_at (g, drv, drv_index);
  /* drv is now owned by the handle */

  /* Call into the appliance to wait for the new drive to appear. */
  if (guestfs_internal_hot_add_drive (g, drv->disk_label) == -1)
    return -1;

  return 0;
}

int
guestfs_impl_add_drive_ro (guestfs_h *g, const char *filename)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .readonly = true,
  };

  return guestfs_add_drive_opts_argv (g, filename, &optargs);
}

int
guestfs_impl_add_drive_with_if (guestfs_h *g, const char *filename,
                            const char *iface)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK,
    .iface = iface,
  };

  return guestfs_add_drive_opts_argv (g, filename, &optargs);
}

int
guestfs_impl_add_drive_ro_with_if (guestfs_h *g, const char *filename,
                               const char *iface)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
             | GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .iface = iface,
    .readonly = true,
  };

  return guestfs_add_drive_opts_argv (g, filename, &optargs);
}

int
guestfs_impl_add_drive_scratch (guestfs_h *g, int64_t size,
                            const struct guestfs_add_drive_scratch_argv *optargs)
{
  struct guestfs_add_drive_opts_argv add_drive_optargs = { .bitmask = 0 };
  CLEANUP_FREE char *filename = NULL;

  /* Some parameters we always set. */
  add_drive_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK;
  add_drive_optargs.format = "raw";
  add_drive_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_CACHEMODE_BITMASK;
  add_drive_optargs.cachemode = "unsafe";

  /* Copy the optional arguments through to guestfs_add_drive_opts. */
  if (optargs->bitmask & GUESTFS_ADD_DRIVE_SCRATCH_NAME_BITMASK) {
    add_drive_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_NAME_BITMASK;
    add_drive_optargs.name = optargs->name;
  }
  if (optargs->bitmask & GUESTFS_ADD_DRIVE_SCRATCH_LABEL_BITMASK) {
    add_drive_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_LABEL_BITMASK;
    add_drive_optargs.label = optargs->label;
  }

  /* Create the temporary file.  We don't have to worry about cleanup
   * because everything in g->tmpdir is 'rm -rf'd when the handle is
   * closed.
   */
  if (guestfs_int_lazy_make_tmpdir (g) == -1)
    return -1;
  filename = safe_asprintf (g, "%s/scratch.%d", g->tmpdir, ++g->unique);

  /* Create a raw format temporary disk. */
  if (guestfs_disk_create (g, filename, "raw", size, -1) == -1)
    return -1;

  /* Call guestfs_add_drive_opts to add the drive. */
  return guestfs_add_drive_opts_argv (g, filename, &add_drive_optargs);
}

int
guestfs_impl_add_cdrom (guestfs_h *g, const char *filename)
{
  return guestfs_impl_add_drive_ro (g, filename);
}

/* Depending on whether we are hotplugging or not, this function
 * does slightly different things: If not hotplugging, then the
 * drive just disappears as if it had never been added.  The later
 * drives "move up" to fill the space.  When hotplugging we have to
 * do some complex stuff, and we usually end up leaving an empty
 * (NULL) slot in the g->drives vector.
 */
int
guestfs_impl_remove_drive (guestfs_h *g, const char *label)
{
  size_t i;
  struct drive *drv;

  ITER_DRIVES (g, i, drv) {
    if (drv->disk_label && STREQ (label, drv->disk_label))
      goto found;
  }
  error (g, _("disk with label '%s' not found"), label);
  return -1;

 found:
  if (g->state == CONFIG) {     /* Not hotplugging. */
    free_drive_struct (drv);

    g->nr_drives--;
    for (; i < g->nr_drives; ++i)
      g->drives[i] = g->drives[i+1];

    return 0;
  }
  else {                        /* Hotplugging. */
    if (!g->backend_ops->hot_remove_drive) {
      error (g, _("the current backend does not support hotplugging drives"));
      return -1;
    }

    if (guestfs_internal_hot_remove_drive_precheck (g, label) == -1)
      return -1;

    if (g->backend_ops->hot_remove_drive (g, g->backend_data, drv, i) == -1)
      return -1;

    free_drive_struct (drv);
    g->drives[i] = NULL;
    if (i == g->nr_drives-1)
      g->nr_drives--;

    if (guestfs_internal_hot_remove_drive (g, label) == -1)
      return -1;

    return 0;
  }
}

/* Checkpoint and roll back drives, so that groups of drives can be
 * added atomicly.  Only used by guestfs_add_domain.
 */
size_t
guestfs_int_checkpoint_drives (guestfs_h *g)
{
  return g->nr_drives;
}

void
guestfs_int_rollback_drives (guestfs_h *g, size_t old_i)
{
  size_t i;

  for (i = old_i; i < g->nr_drives; ++i) {
    if (g->drives[i])
      free_drive_struct (g->drives[i]);
  }
  g->nr_drives = old_i;
}

/* Internal command to return the list of drives. */
char **
guestfs_impl_debug_drives (guestfs_h *g)
{
  size_t i;
  DECLARE_STRINGSBUF (ret);
  struct drive *drv;

  ITER_DRIVES (g, i, drv) {
    guestfs_int_add_string_nodup (g, &ret, drive_to_string (g, drv));
  }

  guestfs_int_end_stringsbuf (g, &ret);

  return ret.argv;              /* caller frees */
}

static void
free_drive_source (struct drive_source *src)
{
  if (src) {
    free (src->format);
    free (src->u.path);
    free (src->username);
    free (src->secret);
    free_drive_servers (src->servers, src->nr_servers);
  }
}
