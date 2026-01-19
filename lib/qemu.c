/* libguestfs
 * Copyright (C) 2009-2025 Red Hat Inc.
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

#include <json.h>

#include "full-write.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

#define CLEANUP_JSON_OBJECT_PUT \
  __attribute__((cleanup(cleanup_json_object_put)))

static void
cleanup_json_object_put (void *ptr)
{
  json_object_put (* (json_object **) ptr);
}

/**
 * Run a generic QMP test on the QEMU binary.
 */
static int
generic_qmp_test (guestfs_h *g, const char *qmp_command, char **outp)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r, fd;
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *line = NULL;
  size_t allocsize = 0;
  ssize_t len;

  guestfs_int_cmd_add_string_unquoted (cmd, "echo ");
  /* QMP is modal.  You have to send the qmp_capabilities command first. */
  guestfs_int_cmd_add_string_unquoted (cmd, "'{ \"execute\": \"qmp_capabilities\" }' ");
  guestfs_int_cmd_add_string_unquoted (cmd, "'{ \"execute\": \"");
  guestfs_int_cmd_add_string_unquoted (cmd, qmp_command);
  guestfs_int_cmd_add_string_unquoted (cmd, "\" }' ");
  /* Exit QEMU after sending the commands. */
  guestfs_int_cmd_add_string_unquoted (cmd, "'{ \"execute\": \"quit\" }' ");
  guestfs_int_cmd_add_string_unquoted (cmd, " | ");
  guestfs_int_cmd_add_string_unquoted (cmd, "QEMU_AUDIO_DRV=none ");
  guestfs_int_cmd_add_string_quoted (cmd, g->hv);
  guestfs_int_cmd_add_string_unquoted (cmd, " -display none");
  guestfs_int_cmd_add_string_unquoted (cmd, " -cpu max");
  guestfs_int_cmd_add_string_unquoted (cmd, " -machine ");
  guestfs_int_cmd_add_string_quoted (cmd,
#ifdef MACHINE_TYPE
                                     MACHINE_TYPE ","
#endif
                                     "accel=kvm:hvf:tcg");
  guestfs_int_cmd_add_string_unquoted (cmd, " -qmp stdio");
  guestfs_int_cmd_clear_capture_errors (cmd);

  fd = guestfs_int_cmd_pipe_run (cmd, "r");
  if (fd == -1)
    return -1;

  /* Read the output line by line.  We expect to see:
   * line 1: {"QMP": {"version": ... } }   # greeting from QMP
   * line 2: {"return": {}}                # output from qmp_capabilities
   * line 3: {"return": ... }              # the data from our qmp_command
   * line 4: {"return": {}}                # output from quit
   * line 5: {"timestamp": ...}            # shutdown event
   */
  fp = fdopen (fd, "r");        /* this will close (fd) at end of scope */
  if (fp == NULL) {
    perrorf (g, "fdopen");
    return -1;
  }
  len = getline (&line, &allocsize, fp); /* line 1 */
  if (len == -1 || strstr (line, "\"QMP\"") == NULL) {
  parse_failure:
    error (g, "did not understand QMP monitor output from %s", g->hv);
    return -1;
  }
  len = getline (&line, &allocsize, fp); /* line 2 */
  if (len == -1 || strstr (line, "\"return\"") == NULL)
    goto parse_failure;
  len = getline (&line, &allocsize, fp); /* line 3 */
  if (len == -1 || strstr (line, "\"return\"") == NULL)
    goto parse_failure;
  *outp = safe_strdup (g, line);
  /* The other lines we don't care about, so finish parsing here. */
  ignore_value (getline (&line, &allocsize, fp)); /* line 4 */
  ignore_value (getline (&line, &allocsize, fp)); /* line 5 */

  r = guestfs_int_cmd_pipe_wait (cmd);
  /* QMP tests are optional, don't fail if the tests fail. */
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    error (g, "%s wait failed or unexpected exit status", g->hv);
    return -1;
  }

  return 0;
}

/**
 * Parse the json output from QMP query-kvm to find out if KVM is
 * enabled on this machine.
 *
 * The JSON output looks like:
 * {"return": {"enabled": true, "present": true}}
 */
static int
parse_has_kvm (guestfs_h *g, const char *json)
{
  CLEANUP_JSON_OBJECT_PUT json_object *tree = NULL;
  json_tokener *tok;
  enum json_tokener_error err;
  json_object *return_node, *enabled_node;

  tok = json_tokener_new ();
  json_tokener_set_flags (tok,
                          JSON_TOKENER_STRICT | JSON_TOKENER_VALIDATE_UTF8);
  tree = json_tokener_parse_ex (tok, json, strlen (json));
  err = json_tokener_get_error (tok);
  if (err != json_tokener_success) {
    error (g, "QMP parse error: %s", json_tokener_error_desc (err));
    json_tokener_free (tok);
    return -1;
  }
  json_tokener_free (tok);

  return_node = json_object_object_get (tree, "return");
  if (json_object_get_type (return_node) != json_type_object) {
    error (g, "QMP query-kvm: no \"return\" node");
    return -1;
  }
  enabled_node = json_object_object_get (return_node, "enabled");
  return json_object_get_boolean (enabled_node);
}

/**
 * Test if the platform supports KVM.
 *
 * Only qemu "knows" this fact reliably, so we run qemu, query it
 * using the QMP "query-kvm" command, and parse the JSON output from
 * that command.
 */
int
guestfs_int_platform_has_kvm (guestfs_h *g)
{
  char *query_kvm;

  if (generic_qmp_test (g, "query-kvm", &query_kvm) == -1)
    return -1;

  return parse_has_kvm (g, query_kvm);
}

/**
 * Escape a qemu parameter.
 *
 * Every C<,> becomes C<,,>.  The caller must free the returned string.
 *
 * XXX This functionality is now only used when constructing a
 * qemu-img command in F<lib/create.c>.  We should extend the qemuopts
 * library to cover this use case.
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
      perrorf (g, _("realpath: could not convert ‘%s’ to absolute path"),
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
    CLEANUP_FREE_STRING_LIST char **hosts = NULL;
    CLEANUP_FREE char *mon_host = NULL, *username = NULL, *secret = NULL;
    const char *auth;
    size_t i;

    /* Build the list of all the mon hosts. */
    hosts = safe_calloc (g, src->nr_servers + 1, sizeof (char *));

    for (i = 0; i < src->nr_servers; i++) {
      CLEANUP_FREE char *escaped_host;

      escaped_host =
        guestfs_int_replace_string (src->servers[i].u.hostname, ":", "\\:");
      if (escaped_host == NULL) g->abort_cb ();
      hosts[i] =
        safe_asprintf (g, "%s\\:%d", escaped_host, src->servers[i].port);
    }
    mon_host = guestfs_int_join_strings ("\\;", hosts);

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

  case drive_protocol_ssh:
    return make_uri (g, "ssh", src->username, src->secret,
                     &src->servers[0], src->u.exportname);
  }

  abort ();
}

/**
 * Test if discard is possible with the underlying file or device.
 * This returns C<1> if discard is possible.  It returns C<0> if not
 * possible and sets the error to the reason why.
 *
 * This function is called when the user set C<discard == "enable">.
 */
bool
guestfs_int_discard_possible (guestfs_h *g, struct drive *drv)
{
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
  else if (STREQ (drv->src.format, "raw") || STREQ (drv->src.format, "qcow2"))
    /* OK */ ;
  else {
    /* It's possible other formats support discard, but we can enable
     * them on a case-by-case basis.
     */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu does not support discard for ‘%s’ format files"),
                   drv->src.format);
  }

  switch (drv->src.protocol) {
    /* Protocols which support discard. */
  case drive_protocol_file:
  case drive_protocol_iscsi:
  case drive_protocol_nbd:
  case drive_protocol_rbd:
    break;

    /* Protocols which don't support discard. */
  case drive_protocol_ftp:
  case drive_protocol_ftps:
  case drive_protocol_http:
  case drive_protocol_https:
  case drive_protocol_ssh:
    NOT_SUPPORTED (g, -1,
                   _("discard cannot be enabled on this drive: "
                     "protocol ‘%s’ does not support discard"),
                   guestfs_int_drive_protocol_to_string (drv->src.protocol));
  }

  return true;
}
