{- libguestfs Haskell bindings
   Copyright (C) 2009-2012 Red Hat Inc.

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

module Guestfs030Config where
import qualified Guestfs
import Control.Monad

main = do
  g <- Guestfs.create

  Guestfs.set_verbose g True
  v <- Guestfs.get_verbose g
  when (v /= True) $
    fail "get_verbose /= True"
  Guestfs.set_verbose g False
  v <- Guestfs.get_verbose g
  when (v /= False) $
    fail "get_verbose /= False"

  Guestfs.set_path g (Just ".")
  p <- Guestfs.get_path g
  when (p /= ".") $
    fail "path not dot"
  Guestfs.set_path g Nothing
  p <- Guestfs.get_path g
  when (p == "") $
    fail "path is empty"

  Guestfs.add_drive_ro g "/dev/null"
  Guestfs.add_drive_ro g "/dev/zero"
