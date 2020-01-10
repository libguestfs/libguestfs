# Example showing how to inspect a virtual machine disk.

import sys
import guestfs

if len(sys.argv) < 2:
    print("inspect_vm: missing disk image to inspect", file=sys.stderr)
    sys.exit(1)
disk = sys.argv[1]

# All new Python code should pass python_return_dict=True
# to the constructor.  It indicates that your program wants
# to receive Python dicts for methods in the API that return
# hashtables.
g = guestfs.GuestFS(python_return_dict=True)

# Attach the disk image read-only to libguestfs.
g.add_drive_opts(disk, readonly=1)

# Run the libguestfs back-end.
g.launch()

# Ask libguestfs to inspect for operating systems.
roots = g.inspect_os()
if len(roots) == 0:
    print("inspect_vm: no operating systems found", file=sys.stderr)
    sys.exit(1)

for root in roots:
    print("Root device: %s" % root)

    # Print basic information about the operating system.
    print("  Product name: %s" % (g.inspect_get_product_name(root)))
    print("  Version:      %d.%d" %
          (g.inspect_get_major_version(root),
           g.inspect_get_minor_version(root)))
    print("  Type:         %s" % (g.inspect_get_type(root)))
    print("  Distro:       %s" % (g.inspect_get_distro(root)))

    # Mount up the disks, like guestfish -i.
    #
    # Sort keys by length, shortest first, so that we end up
    # mounting the filesystems in the correct order.
    mps = g.inspect_get_mountpoints(root)
    for device, mp in sorted(mps.items(), key=lambda k: len(k[0])):
        try:
            g.mount_ro(mp, device)
        except RuntimeError as msg:
            print("%s (ignored)" % msg)

    # If /etc/issue.net file exists, print up to 3 lines.
    filename = "/etc/issue.net"
    if g.is_file(filename):
        print("--- %s ---" % filename)
        lines = g.head_n(3, filename)
        for line in lines:
            print(line)

    # Unmount everything.
    g.umount_all()
