(* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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
 *)

(* Please read generator/README first. *)

open Printf

open Generator_types
open Generator_utils
open Generator_pr
open Generator_docstrings

(* Generate the functions errno_to_string and string_to_errno which
 * convert errno (eg. EINVAL) into string ("EINVAL") and back again,
 * allowing us to portably pass error values over the protocol between
 * different versions of Un*x.
 *)

(* Errors found in POSIX plus additional errors found in the Linux
 * header files.  NOTE keep this sorted and avoid duplicates.
 *)
let errnos = [
  "E2BIG";
  "EACCES";
  "EADDRINUSE";
  "EADDRNOTAVAIL";
  "EADV";
  "EAFNOSUPPORT";
  "EAGAIN";
  "EALREADY";
  "EBADE";
  "EBADF";
  "EBADFD";
  "EBADMSG";
  "EBADR";
  "EBADRQC";
  "EBADSLT";
  "EBFONT";
  "EBUSY";
  "ECANCELED";
  "ECHILD";
  "ECHRNG";
  "ECOMM";
  "ECONNABORTED";
  "ECONNREFUSED";
  "ECONNRESET";
  (*"EDEADLK"; - same as EDEADLOCK*)
  "EDEADLOCK";
  "EDESTADDRREQ";
  "EDOM";
  "EDOTDOT";
  "EDQUOT";
  "EEXIST";
  "EFAULT";
  "EFBIG";
  "EHOSTDOWN";
  "EHOSTUNREACH";
  "EIDRM";
  "EILSEQ";
  "EINPROGRESS";
  "EINTR";
  "EINVAL";
  "EIO";
  "EISCONN";
  "EISDIR";
  "EISNAM";
  "EKEYEXPIRED";
  "EKEYREJECTED";
  "EKEYREVOKED";
  "EL2HLT";
  "EL2NSYNC";
  "EL3HLT";
  "EL3RST";
  "ELIBACC";
  "ELIBBAD";
  "ELIBEXEC";
  "ELIBMAX";
  "ELIBSCN";
  "ELNRNG";
  "ELOOP";
  "EMEDIUMTYPE";
  "EMFILE";
  "EMLINK";
  "EMSGSIZE";
  "EMULTIHOP";
  "ENAMETOOLONG";
  "ENAVAIL";
  "ENETDOWN";
  "ENETRESET";
  "ENETUNREACH";
  "ENFILE";
  "ENOANO";
  "ENOBUFS";
  "ENOCSI";
  "ENODATA";
  "ENODEV";
  "ENOENT";
  "ENOEXEC";
  "ENOKEY";
  "ENOLCK";
  "ENOLINK";
  "ENOMEDIUM";
  "ENOMEM";
  "ENOMSG";
  "ENONET";
  "ENOPKG";
  "ENOPROTOOPT";
  "ENOSPC";
  "ENOSR";
  "ENOSTR";
  "ENOSYS";
  "ENOTBLK";
  "ENOTCONN";
  "ENOTDIR";
  "ENOTEMPTY";
  "ENOTNAM";
  "ENOTRECOVERABLE";
  "ENOTSOCK";
  "ENOTSUP";
  "ENOTTY";
  "ENOTUNIQ";
  "ENXIO";
  (*"EOPNOTSUPP"; - duplicates another error, and we don't care because
    it's a network error *)
  "EOVERFLOW";
  "EOWNERDEAD";
  "EPERM";
  "EPFNOSUPPORT";
  "EPIPE";
  "EPROTO";
  "EPROTONOSUPPORT";
  "EPROTOTYPE";
  "ERANGE";
  "EREMCHG";
  "EREMOTE";
  "EREMOTEIO";
  "ERESTART";
  "ERFKILL";
  "EROFS";
  "ESHUTDOWN";
  "ESOCKTNOSUPPORT";
  "ESPIPE";
  "ESRCH";
  "ESRMNT";
  "ESTALE";
  "ESTRPIPE";
  "ETIME";
  "ETIMEDOUT";
  "ETOOMANYREFS";
  "ETXTBSY";
  "EUCLEAN";
  "EUNATCH";
  "EUSERS";
  (*"EWOULDBLOCK"; - same as EAGAIN*)
  "EXDEV";
  "EXFULL";

  (* This is a non-existent errno which is simply used to test that
   * the generated code can handle such cases on future platforms
   * where one of the above error codes might not exist.
   *)
  "EZZZ";
]

let () =
  (* Check list is sorted and no duplicates. *)
  let file = "generator/generator_errnostring.ml" in
  let check str =
    let len = String.length str in
    if len == 0 || len > 32 then
      failwithf "%s: errno empty or length > 32 (%s)" file str;
    if str.[0] <> 'E' then
      failwithf "%s: errno string does not begin with letter 'E' (%s)" file str;
    for i = 0 to len-1 do
      let c = str.[i] in
      if Char.uppercase c <> c then
        failwithf "%s: errno string is not all uppercase (%s)" file str
    done
  in
  let rec loop = function
    | [] -> ()
    | x :: y :: xs when x = y ->
        failwithf "%s: errnos list contains duplicates (%s)" file x
    | x :: y :: xs when x > y ->
        failwithf "%s: errnos list is not sorted (%s > %s)" file x y
    | x :: xs -> check x; loop xs
  in
  loop errnos

let generate_errnostring_h () =
  generate_header CStyle LGPLv2plus;

  pr "
#ifndef GUESTFS_ERRNOSTRING_H_
#define GUESTFS_ERRNOSTRING_H_

/* Convert errno (eg. EIO) to its string representation (\"EIO\").
 * This only works for a set of errors that are listed in the generator
 * AND are supported on the local operating system.  For other errors
 * the string (\"EINVAL\") is returned.
 *
 * NOTE: It is an error to call this function with errnum == 0.
 */
extern const char *guestfs___errno_to_string (int errnum);

/* Convert string representation of an error (eg. \"EIO\") to the errno
 * value (EIO).  As for the function above, this only works for a
 * subset of errors.  For errors not supported by the local operating
 * system, EINVAL is returned (all POSIX-conforming systems must
 * support EINVAL).
 */
//extern int guestfs___string_to_errno (const char *errnostr);

#endif /* GUESTFS_ERRNOSTRING_H_ */
"

let generate_errnostring_c () =
  generate_header CStyle LGPLv2plus;

  pr "\
#include <config.h>

#include <stdlib.h>
#include <errno.h>

#include \"errnostring.h\"

static const char *errno_to_string[] = {
";

  List.iter (
    fun e ->
      pr "#ifdef %s\n" e;
      pr "  [%s] = \"%s\",\n" e e;
      pr "#endif\n"
  ) errnos;

  pr "\
};

#define ERRNO_TO_STRING_SIZE \\
  (sizeof errno_to_string / sizeof errno_to_string[0])

const char *
guestfs___errno_to_string (int errnum)
{
  /* See function documentation. */
  if (errnum == 0)
    abort ();

  if (errnum < 0 || (size_t) errnum >= ERRNO_TO_STRING_SIZE ||
      errno_to_string[errnum] == NULL)
    return \"EINVAL\";
  else
    return errno_to_string[errnum];
}

"
