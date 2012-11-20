-- Example showing how to inspect a virtual machine disk.

local G = require "guestfs"

if table.getn (arg) == 1 then
   disk = arg[1]
else
   error ("usage: inspect_vm disk.img")
end

local g = G.create ()

-- Attach the disk image read-only to libguestfs.
g:add_drive (disk, { -- format:"raw"
                     readonly = true })

-- Run the libguestfs back-end.
g:launch ()

-- Ask libguestfs to inspect for operating systems.
local roots = g:inspect_os ()
if table.getn (roots) == 0 then
   error ("inspect_vm: no operating systems found")
end

for _, root in ipairs (roots) do
   print ("Root device: ", root)

   -- Print basic information about the operating system.
   print ("  Product name: ", g:inspect_get_product_name (root))
   print ("  Version:      ",
          g:inspect_get_major_version (root),
          g:inspect_get_minor_version (root))
   print ("  Type:         ", g:inspect_get_type (root))
   print ("  Distro:       ", g:inspect_get_distro (root))

   -- Mount up the disks, like guestfish -i.
   --
   -- Sort keys by length, shortest first, so that we end up
   -- mounting the filesystems in the correct order.
   mps = g:inspect_get_mountpoints (root)
   table.sort (mps,
               function (a, b)
                  return string.len (a) < string.len (b)
               end)
   for mp,dev in pairs (mps) do
      pcall (function () g:mount_ro (dev, mp) end)
   end

   -- If /etc/issue.net file exists, print up to 3 lines.
   filename = "/etc/issue.net"
   if g:is_file (filename) then
      print ("--- ", filename, " ---")
      lines = g:head_n (3, filename)
      for _, line in ipairs (lines) do
         print (line)
      end
   end

   -- Unmount everything.
   g:umount_all ()
end
