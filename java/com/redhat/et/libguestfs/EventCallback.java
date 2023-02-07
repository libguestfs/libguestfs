/* libguestfs Java bindings
 * Copyright (C) 2009-2023 Red Hat Inc.
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

package com.redhat.et.libguestfs;

/**
 * Event callback interface.
 * <p>
 * This is the interface for event callbacks.  See the
 * {@link GuestFS#set_event_callback set_event_callback method}
 * for details.
 *
 * @author rjones
 * @see GuestFS
 */
public interface EventCallback {
  public void event (long event, int eh, String buffer, long[] array);
}
