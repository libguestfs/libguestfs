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
use crate::utils;
use std::convert;
use std::ffi;
use std::io;
use std::os::raw::{c_char, c_int};
use std::str;

#[link(name = "guestfs")]
extern "C" {
    fn guestfs_last_error(g: *mut base::guestfs_h) -> *const c_char;
    fn guestfs_last_errno(g: *mut base::guestfs_h) -> c_int;
}

#[derive(Debug)]
pub struct APIError {
    operation: &'static str,
    message: String,
    errno: i32,
}

#[derive(Debug)]
pub enum Error {
    API(APIError),
    IllegalString(ffi::NulError),
    Utf8Error(str::Utf8Error),
    UnixError(io::Error, &'static str),
    Create,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::API(err) => {
                write!(
                    f,
                    "API Error:\n\tOperation: {}\n\tMessage: {}\n\tError Number: {}",
                    err.operation, err.message, err.errno
                )
            }
            Error::IllegalString(err) => {
                write!(
                    f,
                    "Illegal string Error:\nNull byte found\n\tDetails: {}",
                    err
                )
            }
            Error::Utf8Error(err) => {
                write!(
                    f,
                    "Utf8 Error:\nFailed to interpret string as utf-8\n\tDetails: {}",
                    err
                )
            }
            Error::UnixError(err, op) => {
                write!(f, "Unix Error:\n\tError: {}\n\tOperation: {}", err, op)
            }
            Error::Create => {
                write!(f, "Creation Error:\nFailed to create a guestfs handle")
            }
        }
    }
}

impl std::error::Error for Error {}

impl convert::From<ffi::NulError> for Error {
    fn from(error: ffi::NulError) -> Self {
        Error::IllegalString(error)
    }
}

impl convert::From<str::Utf8Error> for Error {
    fn from(error: str::Utf8Error) -> Self {
        Error::Utf8Error(error)
    }
}

pub(crate) fn unix_error(operation: &'static str) -> Error {
    Error::UnixError(io::Error::last_os_error(), operation)
}

impl<'a> base::Handle<'a> {
    pub(crate) fn get_error_from_handle(&self, operation: &'static str) -> Error {
        let c_msg = unsafe { guestfs_last_error(self.g) };
        let message = unsafe { utils::char_ptr_to_string(c_msg).unwrap() };
        let errno = unsafe { guestfs_last_errno(self.g) };
        Error::API(APIError {
            operation,
            message,
            errno,
        })
    }
}
