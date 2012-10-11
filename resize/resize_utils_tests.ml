(* virt-resize
 * Copyright (C) 2011 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(* This file tests the Resize_utils module. *)

open Resize_utils

(* Test Resize_utils.int_of_le32 and Resize_utils.le32_of_int. *)
let () =
  assert (int_of_le32 "\x80\x60\x40\x20" = 0x20406080L);
  assert (le32_of_int 0x20406080L = "\x80\x60\x40\x20")

(* Test Resize_utils.canonicalize. *)
let () =
  assert (canonicalize "/dev/vda" = "/dev/sda");
  assert (canonicalize "/dev/hda3" = "/dev/sda3");
  assert (canonicalize "/dev/sda4" = "/dev/sda4");
  assert (canonicalize "/dev/hdaa" = "/dev/sdaa");
  assert (canonicalize "/dev/sdaa" = "/dev/sdaa");
  assert (canonicalize "/dev/cciss/c0d0p1" = "/dev/cciss/c0d0p1")

(* Test Resize_utils.parse_size. *)
let () =
  (* For absolute sizes, oldsize is ignored. *)
  assert (parse_size 100_L "100b" = 100_L);
  assert (parse_size 1000_L "100b" = 100_L);
  assert (parse_size 10000_L "100b" = 100_L);
  assert (parse_size 100_L "100K" = 102400_L);
  (* Fractions are always rounded down. *)
  assert (parse_size 100_L "1.1K" = 1126_L);
  assert (parse_size 100_L "100.1M" = 104962457_L);
  assert (parse_size 100_L "123.4G" = 132499741081_L);

  (* oldsize +/- a constant. *)
  assert (parse_size 100_L "+1b" = 101_L);
  assert (parse_size 100_L "-2b" = 98_L);
  assert (parse_size 100_L "+1K" = 1124_L);
  assert (parse_size 1024_L "-1K" = 0_L);
  assert (parse_size 1126_L "-1.1K" = 0_L);
  assert (parse_size 1024_L "+1.1M" = 1154457_L);
  assert (parse_size 132499741081_L "-123.3G" = 107374182_L);

  (* oldsize +/- a percentage. *)
  assert (parse_size 100_L "+1%" = 101_L);
  assert (parse_size 100_L "-1%" = 99_L);
  assert (parse_size 100000_L "+1%" = 101000_L);
  assert (parse_size 100000_L "-1%" = 99000_L);
  assert (parse_size 100000_L "+50%" = 150000_L);
  assert (parse_size 100000_L "-50%" = 50000_L);
  assert (parse_size 100000_L "+100%" = 200000_L);
  assert (parse_size 100000_L "-100%" = 0_L);
  assert (parse_size 100000_L "+200%" = 300000_L);
  assert (parse_size 100000_L "+300%" = 400000_L);

  (* Implementation rounds numbers so that only a single digit after
   * the decimal point is significant.
   *)
  assert (parse_size 100000_L "+1.1%" = 101100_L);
  assert (parse_size 100000_L "+1.12%" = 101100_L)

(* Test Resize_utils.human_size. *)
let () =
  assert (human_size 100_L = "100");
  assert (human_size (-100_L) = "-100");
  assert (human_size 1024_L = "1.0K");
  assert (human_size (-1024_L) = "-1.0K");
  assert (human_size 1126_L = "1.1K");
  assert (human_size (-1126_L) = "-1.1K");
  assert (human_size 1363149_L = "1.3M");
  assert (human_size (-1363149_L) = "-1.3M");
  assert (human_size 3650722201_L = "3.4G");
  assert (human_size (-3650722201_L) = "-3.4G")
