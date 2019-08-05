/* libguestfs Rust bindings
 * Copyright (C) 2019 Hiroyuki Katsura <hiroyuki.katsura.0513@gmail.com>
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

use crate::base;
use crate::error;
use crate::guestfs;
use crate::utils;
use std::os::raw::{c_char, c_void};
use std::slice;

type GuestfsEventCallback = extern "C" fn(
    *const base::guestfs_h,
    *const c_void,
    u64,
    i32,
    i32,
    *const i8,
    usize,
    *const u64,
    usize,
);

#[link(name = "guestfs")]
extern "C" {
    fn guestfs_set_event_callback(
        g: *const base::guestfs_h,
        cb: GuestfsEventCallback,
        event_bitmask: u64,
        flags: i32,
        opaque: *const c_void,
    ) -> i32;
    fn guestfs_delete_event_callback(g: *const base::guestfs_h, eh: i32);
    fn guestfs_event_to_string(bitmask: u64) -> *const c_char;
    fn free(buf: *const c_void);
}

#[derive(Hash, PartialEq, Eq)]
pub struct EventHandle {
    eh: i32,
}

fn events_to_bitmask(v: &[guestfs::Event]) -> u64 {
    let mut r = 0u64;
    for x in v.iter() {
        r |= x.to_u64();
    }
    r
}

pub fn event_to_string(events: &[guestfs::Event]) -> Result<String, error::Error> {
    let bitmask = events_to_bitmask(events);

    let r = unsafe { guestfs_event_to_string(bitmask) };
    if r.is_null() {
        Err(error::unix_error("event_to_string"))
    } else {
        let s = unsafe { utils::char_ptr_to_string(r) };
        unsafe { free(r as *const c_void) };
        Ok(s?)
    }
}

impl<'a> base::Handle<'a> {
    pub fn set_event_callback<C: 'a>(
        &mut self,
        callback: C,
        events: &[guestfs::Event],
    ) -> Result<EventHandle, error::Error>
    where
        C: Fn(guestfs::Event, EventHandle, &[u8], &[u64]) + 'a,
    {
        extern "C" fn trampoline<C>(
            _g: *const base::guestfs_h,
            opaque: *const c_void,
            event: u64,
            event_handle: i32,
            _flags: i32,
            buf: *const c_char,
            buf_len: usize,
            array: *const u64,
            array_len: usize,
        ) where
            C: Fn(guestfs::Event, EventHandle, &[u8], &[u64]),
        {
            // trampoline function
            // c.f. https://s3.amazonaws.com/temp.michaelfbryan.com/callbacks/index.html

            let event = match guestfs::Event::from_bitmask(event) {
                Some(x) => x,
                None => panic!("Failed to parse bitmask: {}", event),
            };
            let eh = EventHandle { eh: event_handle };
            let buf = unsafe { slice::from_raw_parts(buf as *const u8, buf_len) };
            let array = unsafe { slice::from_raw_parts(array, array_len) };

            let callback: &Box<dyn Fn(guestfs::Event, EventHandle, &[u8], &[u64])> =
                Box::leak(unsafe { Box::from_raw(opaque as *mut _) });
            callback(event, eh, buf, array)
        }

        // Because trait pointer is fat pointer, in order to pass it to API,
        // double Box is used.
        let callback: Box<Box<dyn Fn(guestfs::Event, EventHandle, &[u8], &[u64]) + 'a>> =
            Box::new(Box::new(callback));
        let ptr = Box::into_raw(callback);
        let callback = unsafe { Box::from_raw(ptr) };
        let event_bitmask = events_to_bitmask(events);

        let eh = {
            unsafe {
                guestfs_set_event_callback(
                    self.g,
                    trampoline::<C>,
                    event_bitmask,
                    0,
                    ptr as *const c_void,
                )
            }
        };
        if eh == -1 {
            return Err(self.get_error_from_handle("set_event_callback"));
        }
        self.callbacks.insert(EventHandle { eh }, callback);

        Ok(EventHandle { eh })
    }

    pub fn delete_event_callback(&mut self, eh: EventHandle) -> Result<(), error::Error> {
        unsafe {
            guestfs_delete_event_callback(self.g, eh.eh);
        }
        self.callbacks.remove(&eh);
        Ok(())
    }
}
