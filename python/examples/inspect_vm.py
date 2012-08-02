# Example showing how to inspect a virtual machine disk.

import sys
import guestfs

assert (len (sys.argv) == 2)
disk = sys.argv[1]

g = guestfs.GuestFS ()

# Attach the disk image read-only to libguestfs.
g.add_drive_opts (disk, readonly=1)

# Run the libguestfs back-end.
g.launch ()

# Ask libguestfs to inspect for operating systems.
roots = g.inspect_os ()
if len (roots) == 0:
    raise (Error ("inspect_vm: no operating systems found"))

for root in roots:
    print "Root device: %s" % root

    # Print basic information about the operating system.
    print "  Product name: %s" % (g.inspect_get_product_name (root))
    print "  Version:      %d.%d" % \
        (g.inspect_get_major_version (root),
         g.inspect_get_minor_version (root))
    print "  Type:         %s" % (g.inspect_get_type (root))
    print "  Distro:       %s" % (g.inspect_get_distro (root))

    # Mount up the disks, like guestfish -i.
    #
    # Sort keys by length, shortest first, so that we end up
    # mounting the filesystems in the correct order.
    mps = g.inspect_get_mountpoints (root)
    def compare (a, b):
        if len(a[0]) > len(b[0]):
            return 1
        elif len(a[0]) == len(b[0]):
            return 0
        else:
            return -1
    mps.sort (compare)
    for mp_dev in mps:
        try:
            g.mount_ro (mp_dev[1], mp_dev[0])
        except RuntimeError as msg:
            print "%s (ignored)" % msg

    # If /etc/issue.net file exists, print up to 3 lines.
    filename = "/etc/issue.net"
    if g.is_file (filename):
        print "--- %s ---" % filename
        lines = g.head_n (3, filename)
        for line in lines: print line

    # Unmount everything.
    g.umount_all ()
