# Example showing how to create a disk image.

import os
import guestfs

output = "disk.img"

g = guestfs.GuestFS ()

# Create a raw-format sparse disk image, 512 MB in size.
f = open (output, "w")
f.truncate (512 * 1024 * 1024)
f.close ()

# Set the trace flag so that we can see each libguestfs call.
g.set_trace (1)

# Set the autosync flag so that the disk will be synchronized
# automatically when the libguestfs handle is closed.
g.set_autosync (1)

# Attach the disk image to libguestfs.
g.add_drive_opts (output, format = "raw", readonly = 0)

# Run the libguestfs back-end.
g.launch ()

# Get the list of devices.  Because we only added one drive
# above, we expect that this list should contain a single
# element.
devices = g.list_devices ()
assert (len (devices) == 1)

# Partition the disk as one single MBR partition.
g.part_disk (devices[0], "mbr")

# Get the list of partitions.  We expect a single element, which
# is the partition we have just created.
partitions = g.list_partitions ()
assert (len (partitions) == 1)

# Create a filesystem on the partition.
g.mkfs ("ext4", partitions[0])

# Now mount the filesystem so that we can add files.
g.mount_options ("", partitions[0], "/")

# Create some files and directories.
g.touch ("/empty")
message = "Hello, world\n"
g.write ("/hello", message)
g.mkdir ("/foo")

# This one uploads the local file /etc/resolv.conf into
# the disk image.
g.upload ("/etc/resolv.conf", "/foo/resolv.conf")

# Because 'autosync' was set (above) we can just close the handle
# and the disk contents will be synchronized.  You can also do
# this manually by calling g.umount_all and g.sync.
g.close ()
