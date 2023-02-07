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
 * Libguestfs error class.
 * <p>
 * This exception is thrown when some error occurs when using the
 * libguestfs library.  The error message is always a simple
 * printable string.
 *
 * @author rjones
 * @see Exception
 */
public class LibGuestFSException extends Exception {
    private static final long serialVersionUID = 1L;

    public LibGuestFSException (String msg)
    {
        super (msg);
    }
}
