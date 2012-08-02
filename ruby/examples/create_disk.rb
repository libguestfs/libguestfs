# Example showing how to create a disk image.

require 'guestfs'

output = "disk.img"

g = Guestfs::Guestfs.new()

# Create a raw-format sparse disk image, 512 MB in size.
File.open(output, "w") {
  |f| f.truncate(512 * 1024 * 1024)
}

# Set the trace flag so that we can see each libguestfs call.
g.set_trace(1)

# Attach the disk image to libguestfs.
g.add_drive_opts(output, :format => "raw")

# Run the libguestfs back-end.
g.launch();

# Get the list of devices.  Because we only added one drive
# above, we expect that this list should contain a single
# element.
devices = g.list_devices()
if devices.length != 1 then
  raise "error: expected a single device from list-devices"
end

# Partition the disk as one single MBR partition.
g.part_disk(devices[0], "mbr")

# Get the list of partitions.  We expect a single element, which
# is the partition we have just created.
partitions = g.list_partitions()
if partitions.length != 1 then
  raise "error: expected a single partition from list-partitions"
end

# Create a filesystem on the partition.
g.mkfs("ext4", partitions[0])

# Now mount the filesystem so that we can add files.
g.mount_options("", partitions[0], "/")

# Create some files and directories.
g.touch("/empty")
message = "Hello, world\n"
g.write("/hello", message)
g.mkdir("/foo")

# This one uploads the local file /etc/resolv.conf into
# the disk image.
g.upload("/etc/resolv.conf", "/foo/resolv.conf")

# Because we wrote to the disk and we want to detect write
# errors, call g.shutdown.  You don't need to do this:
# g.close will do it implicitly.
g.shutdown()

# Note also that handles are automatically closed if they are
# reaped by the garbage collector.  You only need to call close
# if you want to close the handle right away.
g.close()
