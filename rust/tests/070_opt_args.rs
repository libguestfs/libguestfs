/* libguestfs Rust bindings
 * Copyright (C) 2019 Hiroyuki Katsura <hiroyuki.katsura.0513@gmail.com>
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

extern crate guestfs;

use std::default::Default;

#[test]
fn no_optargs() {
    let g = guestfs::Handle::create().expect("create");
    g.add_drive("/dev/null", Default::default())
        .expect("add_drive");
}

#[test]
fn one_optarg() {
    let g = guestfs::Handle::create().expect("create");
    g.add_drive(
        "/dev/null",
        guestfs::AddDriveOptArgs {
            readonly: Some(true),
            ..Default::default()
        },
    )
    .expect("add_drive");
}
