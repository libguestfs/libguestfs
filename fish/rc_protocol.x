/* libguestfs - guestfish remote control protocol -*- c -*-
 * Copyright (C) 2009 Red Hat Inc.
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

typedef string guestfish_str<>;

struct guestfish_hello {
  /* Client and server version strings must match exactly.  We change
   * this protocol whenever we want to.
   */
  string vers<>;
};

struct guestfish_call {
  string cmd<>;
  guestfish_str args<>;
  bool exit_on_error;
};

struct guestfish_reply {
  int r;			/* 0 or -1 only. */
};
