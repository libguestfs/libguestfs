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

use crate::error;
use std::collections;
use std::convert::TryFrom;
use std::ffi;
use std::os::raw::{c_char, c_void};
use std::str;

extern "C" {
    fn free(buf: *const c_void);
}

pub(crate) struct NullTerminatedIter<T: Copy + Clone> {
    p: *const *const T,
}

impl<T: Copy + Clone> NullTerminatedIter<T> {
    pub(crate) fn new(p: *const *const T) -> NullTerminatedIter<T> {
        NullTerminatedIter { p }
    }
}

impl<T: Copy + Clone> Iterator for NullTerminatedIter<T> {
    type Item = *const T;
    fn next(&mut self) -> Option<*const T> {
        let r = unsafe { *(self.p) };
        if r.is_null() {
            None
        } else {
            self.p = unsafe { self.p.offset(1) };
            Some(r)
        }
    }
}

#[repr(C)]
pub(crate) struct RawList<T> {
    size: u32,
    ptr: *const T,
}

pub(crate) struct RawListIter<'a, T> {
    current: u32,
    list: &'a RawList<T>,
}

impl<T> RawList<T> {
    fn iter<'a>(&'a self) -> RawListIter<'a, T> {
        RawListIter {
            current: 0,
            list: self,
        }
    }
}

impl<'a, T> Iterator for RawListIter<'a, T> {
    type Item = *const T;
    fn next(&mut self) -> Option<*const T> {
        if self.current >= self.list.size {
            None
        } else {
            let elem = unsafe { self.list.ptr.offset(self.current as isize) };
            self.current += 1;
            Some(elem)
        }
    }
}

pub(crate) fn arg_string_list(v: &[&str]) -> Result<Vec<ffi::CString>, error::Error> {
    let mut w = Vec::new();
    for x in v.iter() {
        let y: &str = x;
        w.push(ffi::CString::new(y)?);
    }
    Ok(w)
}

pub(crate) fn free_string_list(l: *const *const c_char) {
    for buf in NullTerminatedIter::new(l) {
        unsafe { free(buf as *const c_void) };
    }
    unsafe { free(l as *const c_void) };
}

pub(crate) fn hashmap(
    l: *const *const c_char,
) -> Result<collections::HashMap<String, String>, error::Error> {
    let mut map = collections::HashMap::new();
    let mut iter = NullTerminatedIter::new(l);
    while let Some(key) = iter.next() {
        if let Some(val) = iter.next() {
            let key = unsafe { char_ptr_to_string(key) }?;
            let val = unsafe { char_ptr_to_string(val) }?;
            map.insert(key, val);
        } else {
            // Internal Error -> panic
            panic!("odd number of items in hash table");
        }
    }
    Ok(map)
}

pub(crate) fn struct_list<T, S: TryFrom<*const T, Error = error::Error>>(
    l: *const RawList<T>,
) -> Result<Vec<S>, error::Error> {
    let mut v = Vec::new();
    for x in unsafe { &*l }.iter() {
        v.push(S::try_from(x)?);
    }
    Ok(v)
}

pub(crate) fn string_list(l: *const *const c_char) -> Result<Vec<String>, error::Error> {
    let mut v = Vec::new();
    for x in NullTerminatedIter::new(l) {
        let s = unsafe { char_ptr_to_string(x) }?;
        v.push(s);
    }
    Ok(v)
}

pub(crate) unsafe fn char_ptr_to_string(ptr: *const c_char) -> Result<String, str::Utf8Error> {
    fn char_ptr_to_string_inner(ptr: *const c_char) -> Result<String, str::Utf8Error> {
        let s = unsafe { ffi::CStr::from_ptr(ptr) };
        let s = s.to_str()?.to_string();
        Ok(s)
    }
    char_ptr_to_string_inner(ptr)
}
