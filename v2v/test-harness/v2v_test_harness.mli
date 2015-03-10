(* libguestfs v2v test harness
 * Copyright (C) 2015 Red Hat Inc.
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
 *)

(** {1 Virt-v2v test harness}

    This library is used by external repositories that test virt-v2v
    using real disk images.
*)

type test_plan = {
  post_conversion_test : (Guestfs.guestfs -> string -> Xml.doc -> unit) option;
  (** Arbitrary test that can be run after conversion. *)

  boot_plan : boot_plan;
  (** How to test-boot the guest, if at all. *)

  boot_wait_to_write : int;
  (** Guest must write to disk within this nr. seconds (default: 120). *)

  boot_max_time : int;
  (** Max time we'll wait for guest to finish booting (default: 600).
      However this timer is reset if the screenshot matches something in
      the known good set. *)

  boot_idle_time : int;
  (** For Boot_to_idle, no disk activity counts as idle (default: 60). *)

  boot_known_good_screenshots : string list;
  (** List of known-good screenshots.  If the guest screen looks like
      one of these, we will keep waiting regardless of timeouts. *)

  boot_graceful_shutdown : int;
  (** When gracefully shutting down the guest, max time we will wait
      before we kill it (default: 60). *)

  post_boot_test : (Guestfs.guestfs -> string -> Xml.doc -> unit) option;
  (** Arbitrary test that be run after booting. *)
}

and boot_plan =
| No_boot                      (** Don't do the boot test at all. *)
| Boot_to_idle                 (** Boot until VM is idle. *)
| Boot_to_screenshot of string (** Boot until screenshot is displayed. *)

val default_plan : test_plan

val run : test:string -> ?input_disk:string -> ?input_xml:string -> ?test_plan:test_plan -> unit -> unit
(** Run the test.  This will exit with an error code on failure. *)

val skip : test:string -> string -> unit
(** Skip the test.  The string parameter is the reason for skipping. *)
