/* libguestfs Go configuration test
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/* This is called from ./configure to check that golang works
 * and is above the minimum required version.
 */

package main

func main() {
	/* XXX Check for minimum runtime.Version() >= "go1.1.1"
         * Unfortunately go version numbers are not easy to parse.
         * They have the 3 formats "goX.Y.Z", "release.rN" or
         * "weekly.YYYY-MM-DD".  The latter two formats are mostly
         * useless, and the first one is hard to parse.  See also
         * cmpGoVersion in
         * http://web.archive.org/web/20130402235148/http://golang.org/src/cmd/go/get.go?m=text
         */
}
