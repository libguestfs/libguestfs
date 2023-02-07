{- libguestfs Haskell bindings
   Copyright (C) 2009-2023 Red Hat Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
-}

module Guestfs050LVCreate where
import Guestfs as G
import System.IO (openFile, hClose, hSetFileSize, IOMode(WriteMode))
import System.Posix.Files (removeLink)
import Control.Monad

main = do
  g <- G.create
  {- XXX replace with a call to add_drive_scratch once
         optional arguments are supported -}
  fd <- openFile "test-lv-create.img" WriteMode
  hSetFileSize fd (500 * 1024 * 1024)
  hClose fd
  G.add_drive_ro g "test-lv-create.img"
  G.launch g

  G.pvcreate g "/dev/sda"
  G.vgcreate g "VG" ["/dev/sda"]
  G.lvcreate g "LV1" "VG" 200
  G.lvcreate g "LV2" "VG" 200

  lvs <- G.lvs g
  when (lvs /= ["/dev/VG/LV1", "/dev/VG/LV2"]) $
    fail "invalid list of LVs returned"

  removeLink "test-lv-create.img"
