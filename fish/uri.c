/* libguestfs - mini library for parsing -a URI parameters
 * Copyright (C) 2013 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <libintl.h>

#include <libxml/uri.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"
#include "uri.h"

static int is_uri (const char *arg);
static int parse (const char *arg, char **path_ret, char **protocol_ret, char ***server_ret, char **username_ret);
static char *query_get (xmlURIPtr uri, const char *search_name);
static int make_server (xmlURIPtr uri, const char *socket, char ***ret);

int
parse_uri (const char *arg, struct uri *uri_ret)
{
  char *path;
  char *protocol;
  char **server;
  char *username;

  /* Does it look like a URI? */
  if (is_uri (arg)) {
    if (parse (arg, &path, &protocol, &server, &username) == -1)
      return -1;
  }
  else {
    /* Ordinary file. */
    path = strdup (arg);
    if (!path) {
      perror ("strdup");
      return -1;
    }
    protocol = strdup ("file");
    if (!protocol) {
      perror ("strdup");
      free (path);
      return -1;
    }
    server = NULL;
    username = NULL;
  }

  uri_ret->path = path;
  uri_ret->protocol = protocol;
  uri_ret->server = server;
  uri_ret->username = username;
  return 0;
}

/* Does it "look like" a URI?  A short lower-case ASCII string
 * followed by "://" will do.  Note that we properly parse the URI
 * later on using libxml2.
 */
static int
is_uri (const char *arg)
{
  const char *p;

  p = strstr (arg, "://");
  if (!p)
    return 0;

  if (p - arg >= 8)
    return 0;

  for (p--; p >= arg; p--) {
    if (!c_islower (*p))
      return 0;
  }

  return 1;
}

static int
parse (const char *arg, char **path_ret, char **protocol_ret,
           char ***server_ret, char **username_ret)
{
  CLEANUP_XMLFREEURI xmlURIPtr uri = NULL;
  CLEANUP_FREE char *socket = NULL;

  uri = xmlParseURI (arg);
  if (!uri) {
    fprintf (stderr, _("%s: --add: could not parse URI '%s'\n"),
             program_name, arg);
    return -1;
  }

  /* Note we don't do much checking of the parsed URI, since the
   * underlying function 'guestfs_add_drive_opts' will check for us.
   * So just the basics here.
   */
  if (uri->scheme == NULL || STREQ (uri->scheme, "")) {
    /* Probably can never happen. */
    fprintf (stderr, _("%s: %s: scheme of URI is NULL or empty\n"),
             program_name, arg);
    return -1;
  }

  socket = query_get (uri, "socket");

  if (uri->server && STRNEQ (uri->server, "") && socket) {
    fprintf (stderr, _("%s: %s: cannot both a server name and a socket query parameter\n"),
             program_name, arg);
    return -1;
  }

  /* Is this needed? XXX
  if (socket && socket[0] != '/') {
    fprintf (stderr, _("%s: --add %s: socket query parameter must be an absolute path\n"),
             program_name, arg);
    return -1;
  }
  */

  *protocol_ret = strdup (uri->scheme);
  if (*protocol_ret == NULL) {
    perror ("strdup");
    return -1;
  }

  if (make_server (uri, socket, server_ret) == -1) {
    free (*protocol_ret);
    return -1;
  }

  if (uri->user && STRNEQ (uri->user, "")) {
    *username_ret = strdup (uri->user);
    if (*username_ret == NULL) {
      perror ("username");
      free (*protocol_ret);
      guestfs___free_string_list (*server_ret);
      return -1;
    }
  }
  else *username_ret = NULL;

  *path_ret = strdup (uri->path ? uri->path : "");
  if (!*path_ret) {
    perror ("path");
    free (*protocol_ret);
    guestfs___free_string_list (*server_ret);
    free (*username_ret);
    return -1;
  }

  return 0;
}

/* Code inspired by libvirt src/util/viruri.c, written by danpb,
 * released under a compatible license.
 */
static char *
query_get (xmlURIPtr uri, const char *search_name)
{
  /* XXX libvirt uses deprecated uri->query field.  Why? */
  const char *query = uri->query_raw;
  const char *end, *eq;

  if (!query || STREQ (query, ""))
    return NULL;

  while (*query) {
    CLEANUP_FREE char *name = NULL;
    char *value = NULL;

    /* Find the next separator, or end of the string. */
    end = strchr (query, '&');
    if (!end)
      end = strchr(query, ';');
    if (!end)
      end = query + strlen (query);

    /* Find the first '=' character between here and end. */
    eq = strchr(query, '=');
    if (eq && eq >= end) eq = NULL;

    /* Empty section (eg. "&&"). */
    if (end == query)
      goto next;

    /* If there is no '=' character, then we have just "name"
     * and consistent with CGI.pm we assume value is "".
     */
    else if (!eq) {
      name = xmlURIUnescapeString (query, end - query, NULL);
      if (!name) goto no_memory;
    }
    /* Or if we have "name=" here (works around annoying
     * problem when calling xmlURIUnescapeString with len = 0).
     */
    else if (eq+1 == end) {
      name = xmlURIUnescapeString (query, eq - query, NULL);
      if (!name) goto no_memory;
    }
    /* If the '=' character is at the beginning then we have
     * "=value" and consistent with CGI.pm we _ignore_ this.
     */
    else if (query == eq)
      goto next;

    /* Otherwise it's "name=value". */
    else {
      name = xmlURIUnescapeString (query, eq - query, NULL);
      if (!name)
        goto no_memory;
      value = xmlURIUnescapeString (eq+1, end - (eq+1), NULL);
      if (!value) {
        goto no_memory;
      }
    }

    /* Is it the name we're looking for? */
    if (STREQ (name, search_name)) {
      if (!value) {
        value = strdup ("");
        if (!value)
          goto no_memory;
      }
      return value;
    }

    free (value);

  next:
    query = end;
    if (*query)
      query++; /* skip '&' separator */
  }

  /* search_name not found */
  return NULL;

 no_memory:
  perror ("malloc");
  return NULL;
}

/* Construct either a tcp: server list of a unix: server list or
 * nothing at all from '-a' option URI.
 */
static int
make_server (xmlURIPtr uri, const char *socket, char ***ret)
{
  char *server;

  /* If the server part of the URI is specified, then this is a TCP
   * connection.
   */
  if (uri->server && STRNEQ (uri->server, "")) {
    if (uri->port == 0) {
      if (asprintf (&server, "tcp:%s", uri->server) == -1) {
        perror ("asprintf");
        return -1;
      }
    }
    else {
      if (asprintf (&server, "tcp:%s:%d", uri->server, uri->port) == -1) {
        perror ("asprintf");
        return -1;
      }
    }
  }
  /* Otherwise, ?socket query parameter means it's a Unix domain
   * socket connection.
   */
  else if (socket != NULL) {
    if (asprintf (&server, "unix:%s", socket) == -1) {
      perror ("asprintf");
      return -1;
    }
  }
  /* Otherwise, no server parameter is needed. */
  else {
    *ret = NULL;
    return 0;
  }

  /* The .server parameter is in fact a list of strings, although
   * only a singleton is passed by us.
   */
  *ret = malloc (sizeof (char *) * 2);
  if (*ret == NULL) {
    perror ("malloc");
    return -1;
  }
  (*ret)[0] = server;
  (*ret)[1] = NULL;

  return 0;
}
