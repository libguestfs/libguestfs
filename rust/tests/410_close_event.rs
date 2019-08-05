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

use std::cell::RefCell;
use std::rc::Rc;

#[test]
fn close_event() {
    let close_invoked = Rc::new(RefCell::new(0));
    {
        let mut g = guestfs::Handle::create().expect("create");
        g.set_event_callback(
            |_, _, _, _| {
                *close_invoked.borrow_mut() += 1;
            },
            &[guestfs::Event::Close],
        )
        .unwrap();
        assert_eq!(*close_invoked.borrow(), 0);
    }
    assert_eq!(*close_invoked.borrow(), 1);
}
