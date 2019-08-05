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

fn create<'a>() -> guestfs::Handle<'a> {
    match guestfs::Handle::create() {
        Ok(g) => g,
        Err(e) => panic!("fail: {:?}", e),
    }
}

fn ignore(_x: guestfs::Handle, _y: guestfs::Handle, _z: guestfs::Handle) {
    // drop
}

#[test]
fn create_multiple() {
    let x = create();
    let y = create();
    let z = create();
    ignore(x, y, z)
}
