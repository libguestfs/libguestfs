/* libguestfs
 * Copyright (C) 2009-2017 Red Hat Inc.
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
 * Functions to handle qemu versions and features.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>
#include <libintl.h>

#include <libxml/uri.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

struct qemu_data {
  char *qemu_help;              /* Output of qemu -help. */
  char *qemu_devices;           /* Output of qemu -device ? */

  int virtio_scsi;              /* See function
                                   guestfs_int_qemu_supports_virtio_scsi */
};

static int test_qemu (guestfs_h *g, struct qemu_data *data, struct version *qemu_version);
static void parse_qemu_version (guestfs_h *g, const char *, struct version *qemu_version);
static void read_all (guestfs_h *g, void *retv, const char *buf, size_t len);

/* This is saved in the qemu.stat file, so if we decide to change the
 * test_qemu memoization format/data in future, we should increment
 * this to discard any memoized data cached by previous versions of
 * libguestfs.
 */
#define MEMO_GENERATION 1

/**
 * Test qemu binary (or wrapper) runs, and do C<qemu -help> so we know
 * the version of qemu what options this qemu supports, and
 * C<qemu -device ?> so we know what devices are available.
 *
 * The version number of qemu (from the C<-help> output) is saved in
 * C<&qemu_version>.
 *
 * This caches the results in the cachedir so that as long as the qemu
 * binary does not change, calling this is effectively free.
 */
struct qemu_data *
guestfs_int_test_qemu (guestfs_h *g, struct version *qemu_version)
{
  struct qemu_data *data;
  struct stat statbuf;
  CLEANUP_FREE char *cachedir = NULL, *qemu_stat_filename = NULL,
    *qemu_help_filename = NULL, *qemu_devices_filename = NULL;
  int generation;
  uint64_t prev_size, prev_mtime;

  if (stat (g->hv, &statbuf) == -1) {
    perrorf (g, "stat: %s", g->hv);
    return NULL;
  }

  cachedir = guestfs_int_lazy_make_supermin_appliance_dir (g);
  if (cachedir == NULL)
    return NULL;

  qemu_stat_filename = safe_asprintf (g, "%s/qemu.stat", cachedir);
  qemu_help_filename = safe_asprintf (g, "%s/qemu.help", cachedir);
  qemu_devices_filename = safe_asprintf (g, "%s/qemu.devices", cachedir);

  /* Did we previously test the same version of qemu? */
  debug (g, "checking for previously cached test results of %s, in %s",
         g->hv, cachedir);

  {
    CLEANUP_FCLOSE FILE *fp = NULL;
    fp = fopen (qemu_stat_filename, "r");
    if (fp == NULL)
      goto do_test;
    if (fscanf (fp, "%d %" SCNu64 " %" SCNu64,
                &generation, &prev_size, &prev_mtime) != 3) {
      goto do_test;
    }
  }

  if (generation == MEMO_GENERATION &&
      (uint64_t) statbuf.st_size == prev_size &&
      (uint64_t) statbuf.st_mtime == prev_mtime) {
    /* Same binary as before, so read the previously cached qemu -help
     * and qemu -devices ? output.
     */
    if (access (qemu_help_filename, R_OK) == -1 ||
        access (qemu_devices_filename, R_OK) == -1)
      goto do_test;

    debug (g, "loading previously cached test results");

    data = safe_calloc (g, 1, sizeof *data);

    if (guestfs_int_read_whole_file (g, qemu_help_filename,
                                     &data->qemu_help, NULL) == -1) {
      guestfs_int_free_qemu_data (data);
      return NULL;
    }

    parse_qemu_version (g, data->qemu_help, qemu_version);

    if (guestfs_int_read_whole_file (g, qemu_devices_filename,
                                     &data->qemu_devices, NULL) == -1) {
      guestfs_int_free_qemu_data (data);
      return NULL;
    }

    return data;
  }

 do_test:
  data = safe_calloc (g, 1, sizeof *data);

  if (test_qemu (g, data, qemu_version) == -1) {
    guestfs_int_free_qemu_data (data);
    return NULL;
  }

  /* Now memoize the qemu output in the cache directory. */
  debug (g, "saving test results");

  {
    CLEANUP_FCLOSE FILE *fp = NULL;
    fp = fopen (qemu_help_filename, "w");
    if (fp == NULL) {
    help_error:
      perrorf (g, "%s", qemu_help_filename);
      guestfs_int_free_qemu_data (data);
      return NULL;
    }
    if (fprintf (fp, "%s", data->qemu_help) == -1)
      goto help_error;
  }

  {
    CLEANUP_FCLOSE FILE *fp = NULL;
    fp = fopen (qemu_devices_filename, "w");
    if (fp == NULL) {
    devices_error:
      perrorf (g, "%s", qemu_devices_filename);
      guestfs_int_free_qemu_data (data);
      return NULL;
    }
    if (fprintf (fp, "%s", data->qemu_devices) == -1)
      goto devices_error;
  }

  {
    /* Write the qemu.stat file last so that its presence indicates that
     * the qemu.help and qemu.devices files ought to exist.
     */
    CLEANUP_FCLOSE FILE *fp = NULL;
    fp = fopen (qemu_stat_filename, "w");
    if (fp == NULL) {
    stat_error:
      perrorf (g, "%s", qemu_stat_filename);
      guestfs_int_free_qemu_data (data);
      return NULL;
    }
    /* The path to qemu is stored for information only, it is not
     * used when we parse the file.
     */
    if (fprintf (fp, "%d %" PRIu64 " %" PRIu64 " %s\n",
                 MEMO_GENERATION,
                 (uint64_t) statbuf.st_size,
                 (uint64_t) statbuf.st_mtime,
                 g->hv) == -1)
      goto stat_error;
  }

  return data;
}

static int
test_qemu (guestfs_h *g, struct qemu_data *data, struct version *qemu_version)
{
  CLEANUP_CMD_CLOSE struct command *cmd1 = guestfs_int_new_command (g);
  CLEANUP_CMD_CLOSE struct command *cmd2 = guestfs_int_new_command (g);
  int r;

  guestfs_int_cmd_add_arg (cmd1, g->hv);
  guestfs_int_cmd_add_arg (cmd1, "-display");
  guestfs_int_cmd_add_arg (cmd1, "none");
  guestfs_int_cmd_add_arg (cmd1, "-help");
  guestfs_int_cmd_set_stdout_callback (cmd1, read_all, &data->qemu_help,
				       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd1);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  parse_qemu_version (g, data->qemu_help, qemu_version);

  guestfs_int_cmd_add_arg (cmd2, g->hv);
  guestfs_int_cmd_add_arg (cmd2, "-display");
  guestfs_int_cmd_add_arg (cmd2, "none");
  guestfs_int_cmd_add_arg (cmd2, "-machine");
  guestfs_int_cmd_add_arg (cmd2,
#ifdef MACHINE_TYPE
                           MACHINE_TYPE ","
#endif
                           "accel=kvm:tcg");
  guestfs_int_cmd_add_arg (cmd2, "-device");
  guestfs_int_cmd_add_arg (cmd2, "?");
  guestfs_int_cmd_clear_capture_errors (cmd2);
  guestfs_int_cmd_set_stderr_to_stdout (cmd2);
  guestfs_int_cmd_set_stdout_callback (cmd2, read_all, &data->qemu_devices,
				       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd2);
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0)
    goto error;

  return 0;

 error:
  if (r == -1)
    return -1;

  guestfs_int_external_command_failed (g, r, g->hv, NULL);
  return -1;
}

/**
 * Parse the first line of C<qemu_help> into the major and minor
 * version of qemu, but don't fail if parsing is not possible.
 */
static void
parse_qemu_version (guestfs_h *g, const char *qemu_help,
                    struct version *qemu_version)
{
  version_init_null (qemu_version);

  if (guestfs_int_version_from_x_y (g, qemu_version, qemu_help) < 1) {
    debug (g, "%s: failed to parse qemu version string from the first line of the output of '%s -help'.  When reporting this bug please include the -help output.",
           __func__, g->hv);
    return;
  }

  debug (g, "qemu version %d.%d", qemu_version->v_major, qemu_version->v_minor);
}

static void
read_all (guestfs_h *g, void *retv, const char *buf, size_t len)
{
  char **ret = retv;

  *ret = safe_strndup (g, buf, len);
}

/**
 * Test if option is supported by qemu command line (just by grepping
 * the help text).
 */
int
guestfs_int_qemu_supports (guestfs_h *g, const struct qemu_data *data,
                           const char *option)
{
  return strstr (data->qemu_help, option) != NULL;
}

/**
 * Test if device is supported by qemu (currently just greps the
 * C<qemu -device ?> output).
 */
int
guestfs_int_qemu_supports_device (guestfs_h *g,
                                  const struct qemu_data *data,
                                  const char *device_name)
{
  return strstr (data->qemu_devices, device_name) != NULL;
}

static int
old_or_broken_virtio_scsi (const struct version *qemu_version)
{
  /* qemu 1.1 claims to support virtio-scsi but in reality it's broken. */
  if (!guestfs_int_version_ge (qemu_version, 1, 2, 0))
    return 1;

  return 0;
}

/**
 * Test if qemu supports virtio-scsi.
 *
 * Returns C<1> = use virtio-scsi, or C<0> = use virtio-blk.
 */
int
guestfs_int_qemu_supports_virtio_scsi (guestfs_h *g, struct qemu_data *data,
                                       const struct version *qemu_version)
{
  int r;

  /* data->virtio_scsi has these values:
   *   0 = untested (after handle creation)
   *   1 = supported
   *   2 = not supported (use virtio-blk)
   *   3 = test failed (use virtio-blk)
   */
  if (data->virtio_scsi == 0) {
    if (old_or_broken_virtio_scsi (qemu_version))
      data->virtio_scsi = 2;
    else {
      r = guestfs_int_qemu_supports_device (g, data, VIRTIO_SCSI);
      if (r > 0)
        data->virtio_scsi = 1;
      else if (r == 0)
        data->virtio_scsi = 2;
      else
        data->virtio_scsi = 3;
    }
  }

  return data->virtio_scsi == 1;
}

/**
 * Escape a qemu parameter.
 *
 * Every C<,> becomes C<,,>.  The caller must free the returned string.
 */
char *
guestfs_int_qemu_escape_param (guestfs_h *g, const char *param)
{
  size_t i;
  const size_t len = strlen (param);
  char *p, *ret;

  ret = p = safe_malloc (g, len*2 + 1); /* max length of escaped name*/
  for (i = 0; i < len; ++i) {
    *p++ = param[i];
    if (param[i] == ',')
      *p++ = ',';
  }
  *p = '\0';

  return ret;
}

static char *
make_uri (guestfs_h *g, const char *scheme, const char *user,
          const char *password,
          struct drive_server *server, const char *path)
{
  xmlURI uri = { .scheme = (char *) scheme,
                 .user = (char *) user };
  CLEANUP_FREE char *query = NULL;
  CLEANUP_FREE char *pathslash = NULL;
  CLEANUP_FREE char *userauth = NULL;

  /* Need to add a leading '/' to URI paths since xmlSaveUri doesn't. */
  if (path != NULL && path[0] != '/') {
    pathslash = safe_asprintf (g, "/%s", path);
    uri.path = pathslash;
  }
  else
    uri.path = (char *) path;

  /* Rebuild user:password. */
  if (user != NULL && password != NULL) {
    /* Keep the string in an own variable so it can be freed automatically. */
    userauth = safe_asprintf (g, "%s:%s", user, password);
    uri.user = userauth;
  }

  switch (server->transport) {
  case drive_transport_none:
  case drive_transport_tcp:
    uri.server = server->u.hostname;
    uri.port = server->port;
    break;
  case drive_transport_unix:
    query = safe_asprintf (g, "socket=%s", server->u.socket);
    uri.query_raw = query;
    break;
  }

  return (char *) xmlSaveUri (&uri);
}

/**
 * Useful function to format a drive + protocol for qemu.
 *
 * Note that the qemu parameter is the bit after C<"file=">.  It is
 * not escaped here, but would usually be escaped if passed to qemu as
 * part of a full -drive parameter (but not for L<qemu-img(1)>).
 */
char *
guestfs_int_drive_source_qemu_param (guestfs_h *g,
                                     const struct drive_source *src)
{
  char *path;

  switch (src->protocol) {
  case drive_protocol_file:
    /* We have to convert the path to an absolute path, since
     * otherwise qemu will look for the backing file relative to the
     * overlay (which is located in g->tmpdir).
     *
     * As a side-effect this deals with paths that contain ':' since
     * qemu will not process the ':' if the path begins with '/'.
     */
    path = realpath (src->u.path, NULL);
    if (path == NULL) {
      perrorf (g, _("realpath: could not convert '%s' to absolute path"),
               src->u.path);
      return NULL;
    }
    return path;

  case drive_protocol_ftp:
    return make_uri (g, "ftp", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_ftps:
    return make_uri (g, "ftps", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_gluster:
    switch (src->servers[0].transport) {
    case drive_transport_none:
      return make_uri (g, "gluster", NULL, NULL,
                       &src->servers[0], src->u.exportname);
    case drive_transport_tcp:
      return make_uri (g, "gluster+tcp", NULL, NULL,
                       &src->servers[0], src->u.exportname);
    case drive_transport_unix:
      return make_uri (g, "gluster+unix", NULL, NULL,
                       &src->servers[0], NULL);
    }

  case drive_protocol_http:
    return make_uri (g, "http", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_https:
    return make_uri (g, "https", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_iscsi: {
    CLEANUP_FREE char *escaped_hostname = NULL;
    CLEANUP_FREE char *escaped_target = NULL;
    CLEANUP_FREE char *userauth = NULL;
    char port_str[16];
    char *ret;

    escaped_hostname =
      (char *) xmlURIEscapeStr(BAD_CAST src->servers[0].u.hostname,
                               BAD_CAST "");
    /* The target string must keep slash as it is, as exportname contains
     * "iqn/lun".
     */
    escaped_target =
      (char *) xmlURIEscapeStr(BAD_CAST src->u.exportname, BAD_CAST "/");
    if (src->username != NULL && src->secret != NULL)
      userauth = safe_asprintf (g, "%s%%%s@", src->username, src->secret);
    if (src->servers[0].port != 0)
      snprintf (port_str, sizeof port_str, ":%d", src->servers[0].port);

    ret = safe_asprintf (g, "iscsi://%s%s%s/%s",
                         userauth != NULL ? userauth : "",
                         escaped_hostname,
                         src->servers[0].port != 0 ? port_str : "",
                         escaped_target);

    return ret;
  }

  case drive_protocol_nbd: {
    CLEANUP_FREE char *p = NULL;
    char *ret;

    switch (src->servers[0].transport) {
    case drive_transport_none:
    case drive_transport_tcp:
      p = safe_asprintf (g, "nbd:%s:%d",
                         src->servers[0].u.hostname, src->servers[0].port);
      break;
    case drive_transport_unix:
      p = safe_asprintf (g, "nbd:unix:%s", src->servers[0].u.socket);
      break;
    }
    assert (p);

    if (STREQ (src->u.exportname, ""))
      ret = safe_strdup (g, p);
    else
      ret = safe_asprintf (g, "%s:exportname=%s", p, src->u.exportname);

    return ret;
  }

  case drive_protocol_rbd: {
    CLEANUP_FREE char *mon_host = NULL, *username = NULL, *secret = NULL;
    const char *auth;
    size_t n = 0;
    size_t i, j;

    /* build the list of all the mon hosts */
    for (i = 0; i < src->nr_servers; i++) {
      n += strlen (src->servers[i].u.hostname);
      n += 8; /* for slashes, colons, & port numbers */
    }
    n++; /* for \0 */
    mon_host = safe_malloc (g, n);
    n = 0;
    for (i = 0; i < src->nr_servers; i++) {
      CLEANUP_FREE char *port = NULL;

      for (j = 0; j < strlen (src->servers[i].u.hostname); j++)
        mon_host[n++] = src->servers[i].u.hostname[j];
      mon_host[n++] = '\\';
      mon_host[n++] = ':';
      port = safe_asprintf (g, "%d", src->servers[i].port);
      for (j = 0; j < strlen (port); j++)
        mon_host[n++] = port[j];

      /* join each host with \; */
      if (i != src->nr_servers - 1) {
        mon_host[n++] = '\\';
        mon_host[n++] = ';';
      }
    }
    mon_host[n] = '\0';

    if (src->username)
      username = safe_asprintf (g, ":id=%s", src->username);
    if (src->secret)
      secret = safe_asprintf (g, ":key=%s", src->secret);
    if (username || secret)
      auth = ":auth_supported=cephx\\;none";
    else
      auth = ":auth_supported=none";

    return safe_asprintf (g, "rbd:%s%s%s%s%s%s",
                          src->u.exportname,
                          src->nr_servers > 0 ? ":mon_host=" : "",
                          src->nr_servers > 0 ? mon_host : "",
                          username ? username : "",
                          auth,
                          secret ? secret : "");
  }

  case drive_protocol_sheepdog:
    if (src->nr_servers == 0)
      return safe_asprintf (g, "sheepdog:%s", src->u.exportname);
    else                        /* XXX How to pass multiple hosts? */
      return safe_asprintf (g, "sheepdog:%s:%d:%s",
                            src->servers[0].u.hostname, src->servers[0].port,
                            src->u.exportname);

  case drive_protocol_ssh:
    return make_uri (g, "ssh", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_tftp:
    return make_uri (g, "tftp", src->username, src->secret,
                     &src->servers[0], src->u.exportname);
  }

  abort ();
}

/**
 * Test if discard is both supported by qemu AND possible with the
 * underlying file or device.  This returns C<1> if discard is
 * possible.  It returns C<0> if not possible and sets the error to
 * the reason why.
 *
 * This function is called when the user set C<discard == "enable">.
 */
bool
guestfs_int_discard_possible (guestfs_h *g, struct drive *drv,
			      const struct version *qemu_version)
{
  /* qemu >= 1.5.  This was the first version that supported the
   * discard option on -drive at all.
   */
  bool qemu15 = guestfs_int_version_ge (qemu_version, 1, 5, 0);

  if (!qemu15)
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu < 1.5"));

  /* If it's an overlay, discard is not possible (on the underlying
   * file).  This has probably been caught earlier since we already
   * checked that the drive is !readonly.  Nevertheless ...
   */
  if (drv->overlay)
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "the drive has a read-only overlay"));

  /* Look at the source format. */
  if (drv->src.format == NULL) {
    /* We could autodetect the format, but we don't ... yet. XXX */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "you have to specify the format of the file"));
  }
  else if (STREQ (drv->src.format, "raw"))
    /* OK */ ;
  else if (STREQ (drv->src.format, "qcow2"))
    /* OK */ ;
  else {
    /* It's possible in future other formats will support discard, but
     * currently (qemu 1.7) none of them do.
     */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu does not support discard for '%s' format files"),
                   drv->src.format);
  }

  switch (drv->src.protocol) {
    /* Protocols which support discard. */
  case drive_protocol_file:
  case drive_protocol_gluster:
  case drive_protocol_iscsi:
  case drive_protocol_nbd:
  case drive_protocol_rbd:
  case drive_protocol_sheepdog: /* XXX depends on server version */
    break;

    /* Protocols which don't support discard. */
  case drive_protocol_ftp:
  case drive_protocol_ftps:
  case drive_protocol_http:
  case drive_protocol_https:
  case drive_protocol_ssh:
  case drive_protocol_tftp:
    NOT_SUPPORTED (g, -1,
                   _("discard cannot be enabled on this drive: "
                     "protocol '%s' does not support discard"),
                   guestfs_int_drive_protocol_to_string (drv->src.protocol));
  }

  return true;
}

/**
 * Free the C<struct qemu_data>.
 */
void
guestfs_int_free_qemu_data (struct qemu_data *data)
{
  if (data) {
    free (data->qemu_help);
    free (data->qemu_devices);
    free (data);
  }
}
