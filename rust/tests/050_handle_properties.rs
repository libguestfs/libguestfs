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
fn verbose() {
    let g = guestfs::Handle::create().expect("create");
    g.set_verbose(true).expect("set_verbose");
    assert_eq!(g.get_verbose().expect("get_verbose"), true);
    g.set_verbose(false).expect("set_verbose");
    assert_eq!(g.get_verbose().expect("get_verbose"), false);
}

#[test]
fn trace() {
    let g = guestfs::Handle::create().expect("create");
    g.set_trace(true).expect("set_trace");
    assert_eq!(g.get_trace().expect("get_trace"), true);
    g.set_trace(false).expect("set_trace");
    assert_eq!(g.get_trace().expect("get_trace"), false);
}

#[test]
fn autosync() {
    let g = guestfs::Handle::create().expect("create");
    g.set_autosync(true).expect("set_autosync");
    assert_eq!(g.get_autosync().expect("get_autosync"), true);
    g.set_autosync(false).expect("set_autosync");
    assert_eq!(g.get_autosync().expect("get_autosync"), false);
}

#[test]
fn path() {
    let g = guestfs::Handle::create().expect("create");
    g.set_path(Some(".")).expect("set_path");
    assert_eq!(g.get_path().expect("get_path"), ".");
}

#[test]
fn add_drive() {
    let g = guestfs::Handle::create().expect("create");
    g.add_drive("/dev/null", Default::default())
        .expect("add_drive");
}
