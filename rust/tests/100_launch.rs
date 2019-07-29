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
fn launch() {
    let g = guestfs::Handle::create().expect("create");
    g.add_drive_scratch(500 * 1024 * 1024, Default::default())
        .expect("add_drive_scratch");
    g.launch().expect("launch");
    g.pvcreate("/dev/sda").expect("pvcreate");
    g.vgcreate("VG", &["/dev/sda"]).expect("vgcreate");
    g.lvcreate("LV1", "VG", 200).expect("lvcreate");
    g.lvcreate("LV2", "VG", 200).expect("lvcreate");

    let lvs = g.lvs().expect("lvs");
    assert_eq!(
        lvs,
        vec!["/dev/VG/LV1".to_string(), "/dev/VG/LV2".to_string()]
    );

    g.mkfs("ext2", "/dev/VG/LV1", Default::default())
        .expect("mkfs");
    g.mount("/dev/VG/LV1", "/").expect("mount");
    g.mkdir("/p").expect("mkdir");
    g.touch("/q").expect("touch");

    let mut dirs = g.readdir("/").expect("readdir");

    dirs.sort_by(|a, b| a.name.cmp(&b.name));

    let mut v = Vec::new();
    for x in &dirs {
        v.push((x.name.as_str(), x.ftyp as u8));
    }
    assert_eq!(
        v,
        vec![
            (".", b'd'),
            ("..", b'd'),
            ("lost+found", b'd'),
            ("p", b'd'),
            ("q", b'r')
        ]
    );
    g.shutdown().expect("shutdown");
}
