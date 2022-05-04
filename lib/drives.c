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

/**
 * Drives added are stored in an array in the handle.  Code here
 * manages that array and the individual C<struct drive> data.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <libintl.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

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
  const char *name;
  const char *disk_label;
  const char *cachemode;
  enum discard discard;
  bool copyonread;
  int blocksize;
};

COMPILE_REGEXP (re_hostname_port, "(.*):(\\d+)$", 0)

static void free_drive_struct (struct drive *drv);
static void free_drive_source (struct drive_source *src);

/**
 * For readonly drives, create an overlay to protect the original
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

/**
 * Create and free the C<struct drive>.
 */
static struct drive *
create_drive_file (guestfs_h *g,
                   const struct drive_create_data *data)
{
  struct drive *drv = safe_calloc (g, 1, sizeof *drv);

  drv->src.protocol = drive_protocol_file;
  drv->src.u.path = safe_strdup (g, data->exportname);
  drv->src.format = data->format ? safe_strdup (g, data->format) : NULL;

  drv->readonly = data->readonly;
  drv->name = data->name ? safe_strdup (g, data->name) : NULL;
  drv->disk_label = data->disk_label ? safe_strdup (g, data->disk_label) : NULL;
  drv->cachemode = data->cachemode ? safe_strdup (g, data->cachemode) : NULL;
  drv->discard = data->discard;
  drv->copyonread = data->copyonread;
  drv->blocksize = data->blocksize;

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
  drv->name = data->name ? safe_strdup (g, data->name) : NULL;
  drv->disk_label = data->disk_label ? safe_strdup (g, data->disk_label) : NULL;
  drv->cachemode = data->cachemode ? safe_strdup (g, data->cachemode) : NULL;
  drv->discard = data->discard;
  drv->copyonread = data->copyonread;
  drv->blocksize = data->blocksize;

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

/**
 * Create the special F</dev/null> drive.
 *
 * Traditionally you have been able to use F</dev/null> as a filename,
 * as many times as you like.  Ancient KVM (RHEL 5) cannot handle
 * adding F</dev/null> readonly.  qemu 1.2 + virtio-scsi segfaults
 * when you use any zero-sized file including F</dev/null>.
 *
 * Because of these problems, we replace F</dev/null> with a non-zero
 * sized temporary file.  This shouldn't make any difference since
 * users are not supposed to try and access a null drive.
 */
static struct drive *
create_drive_dev_null (guestfs_h *g,
                       struct drive_create_data *data)
{
  CLEANUP_FREE char *tmpfile = NULL;

  if (data->format) {
    if (STRNEQ (data->format, "raw")) {
      error (g, _("for device ‘/dev/null’, format must be ‘raw’"));
      return NULL;
    }
  } else {
    /* Manual set format=raw for /dev/null drives, if that was not
     * already manually specified.  */
    data->format = "raw";
  }

  tmpfile = guestfs_int_make_temp_path (g, "devnull", "img");
  if (tmpfile == NULL)
    return NULL;

  /* Because we create a special file, there is no point forcing qemu
   * to create an overlay as well.  Save time by setting readonly = false.
   */
  data->readonly = false;

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

/**
 * Convert a C<struct drive> to a string for debugging.  The caller
 * must free this string.
 */
static char *
drive_to_string (guestfs_h *g, const struct drive *drv)
{
  CLEANUP_FREE char *s_blocksize = NULL;

  if (drv->blocksize)
    s_blocksize = safe_asprintf (g, "%d", drv->blocksize);

  return safe_asprintf
    (g, "%s%s%s%s protocol=%s%s%s%s%s%s%s%s%s%s%s",
     drv->src.u.path,
     drv->readonly ? " readonly" : "",
     drv->src.format ? " format=" : "",
     drv->src.format ? : "",
     guestfs_int_drive_protocol_to_string (drv->src.protocol),
     drv->name ? " name=" : "",
     drv->name ? : "",
     drv->disk_label ? " label=" : "",
     drv->disk_label ? : "",
     drv->cachemode ? " cache=" : "",
     drv->cachemode ? : "",
     drv->discard == discard_disable ? "" :
     drv->discard == discard_enable ? " discard=enable" : " discard=besteffort",
     drv->copyonread ? " copyonread" : "",
     drv->blocksize ? " blocksize=" : "",
     drv->blocksize ? s_blocksize : "");
}

/**
 * Add C<struct drive> to the C<g-E<gt>drives> vector at the given
 * index C<drv_index>.  If the array isn't large enough it is
 * reallocated.  The index must not contain a drive already.
 */
static void
add_drive_to_handle_at (guestfs_h *g, struct drive *d, size_t drv_index)
{
  if (drv_index >= g->nr_drives) {
    g->drives = safe_realloc (g, g->drives,
                              sizeof (struct drive *) * (drv_index + 1));
    while (g->nr_drives < drv_index+1) {
      g->drives[g->nr_drives] = NULL;
      g->nr_drives++;
    }
  }

  assert (g->drives[drv_index] == NULL);

  g->drives[drv_index] = d;
}

/**
 * Add struct drive to the end of the C<g-E<gt>drives> vector in the
 * handle.
 */
static void
add_drive_to_handle (guestfs_h *g, struct drive *d)
{
  add_drive_to_handle_at (g, d, g->nr_drives);
}

/**
 * Called during launch to add a dummy slot to C<g-E<gt>drives>.
 */
void
guestfs_int_add_dummy_appliance_drive (guestfs_h *g)
{
  struct drive *drv;

  drv = create_drive_dummy (g);
  add_drive_to_handle (g, drv);
}

/**
 * Free up all the drives in the handle.
 */
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

/**
 * Check string parameter matches regular expression
 * C<^[-_[:alnum:]]+$> (in C locale).
 */
#define VALID_FORMAT(str) \
  guestfs_int_string_is_valid ((str), 1, 0, \
                               VALID_FLAG_ALPHA|VALID_FLAG_DIGIT, "-_")

/**
 * Check the disk label is reasonable.  It can't contain certain
 * characters, eg. C<'/'>, C<','>.  However be stricter here and
 * ensure it's just alphabetic and E<le> 20 characters in length.
 */
#define VALID_DISK_LABEL(str) \
  guestfs_int_string_is_valid ((str), 1, 20, VALID_FLAG_ALPHA, NULL)

/**
 * Check the server hostname is reasonable.
 */
#define VALID_HOSTNAME(str) \
  guestfs_int_string_is_valid ((str), 1, 255, \
                               VALID_FLAG_ALPHA|VALID_FLAG_DIGIT, "-.:[]")

/**
 * Check the port number is reasonable.
 */
static int
valid_port (int port)
{
  if (port <= 0 || port > 65535)
    return 0;
  return 1;
}

/**
 * Check the block size is reasonable.  It can't be other then 512 or 4096.
 */
static int
valid_blocksize (int blocksize)
{
  if (blocksize == 512 || blocksize == 4096)
    return 1;
  return 0;
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
      error (g, _("invalid port number ‘%s’"), port_str);
      free (hostname);
      free (port_str);
      return -1;
    }
    free (port_str);
    if (!VALID_HOSTNAME (hostname)) {
      error (g, _("invalid hostname ‘%s’"), hostname);
      free (hostname);
      return -1;
    }
    ret->u.hostname = hostname;
    ret->port = port;
    return 0;
  }

  /* Doesn't match anything above, so assume it's a bare hostname. */
  if (!VALID_HOSTNAME (server)) {
    error (g, _("invalid hostname or server string ‘%s’"), server);
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
  const size_t n = guestfs_int_count_strings (strs);
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

  data.nr_servers = 0;
  data.servers = NULL;
  data.exportname = filename;

  data.readonly = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK
    ? optargs->readonly : false;
  data.format = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK
    ? optargs->format : NULL;
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
      error (g, _("discard parameter must be ‘disable’, ‘enable’ or ‘besteffort’"));
      free_drive_servers (data.servers, data.nr_servers);
      return -1;
    }
  }
  else
    data.discard = discard_disable;

  data.copyonread =
    optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_COPYONREAD_BITMASK
    ? optargs->copyonread : false;

  data.blocksize =
    optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_BLOCKSIZE_BITMASK
    ? optargs->blocksize : 0;

  if (data.readonly && data.discard == discard_enable) {
    error (g, _("discard support cannot be enabled on read-only drives"));
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }

  if (data.format && !VALID_FORMAT (data.format)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "format");
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }
  if (data.disk_label && !VALID_DISK_LABEL (data.disk_label)) {
    error (g, _("label parameter is empty, too long, or contains disallowed characters"));
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }
  if (data.cachemode &&
      !(STREQ (data.cachemode, "writeback") || STREQ (data.cachemode, "unsafe"))) {
    error (g, _("cachemode parameter must be ‘writeback’ (default) or ‘unsafe’"));
    free_drive_servers (data.servers, data.nr_servers);
    return -1;
  }
  if (data.blocksize && !valid_blocksize (data.blocksize)) {
    error (g, _("%s parameter is invalid"), "blocksize");
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
  else if (STREQ (protocol, "nbd")) {
    data.protocol = drive_protocol_nbd;
    drv = create_drive_nbd (g, &data);
  }
  else if (STREQ (protocol, "rbd")) {
    data.protocol = drive_protocol_rbd;
    drv = create_drive_rbd (g, &data);
  }
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
  else {
    error (g, _("unknown protocol ‘%s’"), protocol);
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

  /* ... else the old hotplugging case */
  error (g, _("hotplugging support was removed in libguestfs 1.48"));
  return -1;
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
				const char *iface ATTRIBUTE_UNUSED)
{
  return guestfs_add_drive_opts_argv (g, filename, NULL);
}

int
guestfs_impl_add_drive_ro_with_if (guestfs_h *g, const char *filename,
                               const char *iface ATTRIBUTE_UNUSED)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
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
  if (optargs->bitmask & GUESTFS_ADD_DRIVE_SCRATCH_BLOCKSIZE_BITMASK) {
    add_drive_optargs.bitmask |= GUESTFS_ADD_DRIVE_OPTS_BLOCKSIZE_BITMASK;
    add_drive_optargs.blocksize = optargs->blocksize;
  }

  /* Create the temporary file.  We don't have to worry about cleanup
   * because everything in g->tmpdir is 'rm -rf'd when the handle is
   * closed.
   */
  filename = guestfs_int_make_temp_path (g, "scratch", "img");
  if (!filename)
    return -1;

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

int
guestfs_impl_remove_drive (guestfs_h *g, const char *label)
{
  error (g, _("hotplugging support was removed in libguestfs 1.48"));
  return -1;
}

/**
 * Checkpoint and roll back drives, so that groups of drives can be
 * added atomically.  Only used by L<guestfs(3)/guestfs_add_domain>.
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

/**
 * Internal function to return the list of drives.
 */
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

int
guestfs_impl_device_index (guestfs_h *g, const char *device)
{
  size_t len;
  ssize_t r = -1;

  /* /dev/hd etc. */
  if (STRPREFIX (device, "/dev/") &&
      strchr (device+5, '/') == NULL && /* not an LV name */
      device[5] != 'm' && /* not /dev/md - RHBZ#1414682 */
      ((len = strcspn (device+5, "d")) > 0 && len <= 2))
    r = guestfs_int_drive_index (device+5+len+1);

  if (r == -1)
    error (g, _("%s: device not found"), device);
  return r;
}

char *
guestfs_impl_device_name (guestfs_h *g, int index)
{
  char drive_name[64];

  if (index < 0 || index >= g->nr_drives) {
    guestfs_int_error_errno (g, EINVAL, _("drive index out of range"));
    return NULL;
  }

  guestfs_int_drive_name (index, drive_name);
  return safe_asprintf (g, "/dev/sd%s", drive_name);
}
