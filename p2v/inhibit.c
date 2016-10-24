/* virt-p2v
 * Copyright (C) 2016 Red Hat Inc.
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

/**
 * This file is used to inhibit power saving, sleep, suspend etc during
 * the conversion.
 *
 * The method it uses is to send a D-Bus message to logind, as
 * described here:
 *
 * https://www.freedesktop.org/wiki/Software/systemd/inhibit/
 *
 * If virt-p2v is compiled without D-Bus support then this does nothing.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_DBUS
#include <dbus/dbus.h>
#endif

#include "p2v.h"

/**
 * Inhibit all forms of power saving.  A file descriptor is returned,
 * and when the file descriptor is closed the inhibit is stopped.
 *
 * If the function returns C<-1> then C<Inhibit> operation could not
 * be performed (eg. if we are compiled without D-Bus support, or there
 * is some error contacting logind).  This is not usually fatal from
 * the point of view of the caller, conversion can continue.
 */
int
inhibit_power_saving (void)
{
#ifdef HAVE_DBUS
  DBusError err;
  DBusConnection *conn = NULL;
  DBusMessage *msg = NULL;
  DBusMessageIter args;
  DBusPendingCall *pending = NULL;
  const char *what = "shutdown:sleep:idle";
  const char *who = "virt-p2v";
  const char *why = "virt-p2v conversion is running";
  const char *mode = "block";
  int fd = -1;

  dbus_error_init (&err);

  conn = dbus_bus_get (DBUS_BUS_SYSTEM, &err);
  if (dbus_error_is_set (&err)) {
    fprintf (stderr, "inhibit_power_saving: dbus: cannot connect to system bus: %s\n", err.message);
    goto out;
  }
  if (conn == NULL)
    goto out;

  msg = dbus_message_new_method_call ("org.freedesktop.login1",
                                      "/org/freedesktop/login1",
                                      "org.freedesktop.login1.Manager",
                                      "Inhibit");
  if (msg == NULL) {
    fprintf (stderr, "inhibit_power_saving: dbus: cannot create message\n");
    goto out;
  }

  dbus_message_iter_init_append (msg, &args);
  if (!dbus_message_iter_append_basic (&args, DBUS_TYPE_STRING, &what) ||
      !dbus_message_iter_append_basic (&args, DBUS_TYPE_STRING, &who) ||
      !dbus_message_iter_append_basic (&args, DBUS_TYPE_STRING, &why) ||
      !dbus_message_iter_append_basic (&args, DBUS_TYPE_STRING, &mode)) {
    fprintf (stderr, "inhibit_power_saving: dbus: cannot add message arguments\n");
    goto out;
  }

  if (!dbus_connection_send_with_reply (conn, msg, &pending, -1)) {
    fprintf (stderr, "inhibit_power_saving: dbus: cannot send Inhibit message to logind\n");
    goto out;
  }
  if (pending == NULL)
    goto out;
  dbus_connection_flush (conn);

  dbus_message_unref (msg);
  msg = NULL;

  dbus_pending_call_block (pending);
  msg = dbus_pending_call_steal_reply (pending);
  if (msg == NULL) {
    fprintf (stderr, "inhibit_power_saving: dbus: could not read message reply\n");
    goto out;
  }

  dbus_pending_call_unref (pending);
  pending = NULL;

  if (!dbus_message_iter_init (msg, &args)) {
    fprintf (stderr, "inhibit_power_saving: dbus: message reply has no return value\n");
    goto out;
  }

  if (dbus_message_iter_get_arg_type (&args) != DBUS_TYPE_UNIX_FD) {
    fprintf (stderr, "inhibit_power_saving: dbus: message reply is not a file descriptor\n");
    goto out;
  }

  dbus_message_iter_get_basic (&args, &fd);

#ifdef DEBUG_STDERR
  fprintf (stderr, "inhibit_power_saving: dbus: Inhibit() call returned file descriptor %d\n", fd);
#endif

out:
  if (pending != NULL)
    dbus_pending_call_unref (pending);
  if (msg != NULL)
    dbus_message_unref (msg);

  /* This is the system bus connection, so unref-ing it does not
   * actually close it.
   */
  if (conn != NULL)
    dbus_connection_unref (conn);

  dbus_error_free (&err);

  return fd;

#else /* !HAVE_DBUS */
#ifdef DEBUG_STDERR
  fprintf (stderr, "warning: virt-p2v compiled without D-Bus support.\n");
#endif
  return -1;
#endif
}
