#!/usr/bin/env perl

# Example showing how to inspect a virtual machine disk.

use strict;
use warnings;
use Sys::Guestfs;

if (@ARGV < 1) {
    die "usage: inspect_vm disk.img"
}

my $disk = $ARGV[0];

my $g = new Sys::Guestfs ();

# Attach the disk image read-only to libguestfs.
# You could also add an optional format => ... argument here.  This is
# advisable since automatic format detection is insecure.
$g->add_drive_opts ($disk, readonly => 1);

# Run the libguestfs back-end.
$g->launch ();

# Ask libguestfs to inspect for operating systems.
my @roots = $g->inspect_os ();
if (@roots == 0) {
    die "inspect_vm: no operating systems found";
}

for my $root (@roots) {
    printf "Root device: %s\n", $root;

    # Print basic information about the operating system.
    printf "  Product name: %s\n", $g->inspect_get_product_name ($root);
    printf "  Version:      %d.%d\n",
        $g->inspect_get_major_version ($root),
        $g->inspect_get_minor_version ($root);
    printf "  Type:         %s\n", $g->inspect_get_type ($root);
    printf "  Distro:       %s\n", $g->inspect_get_distro ($root);

    # Mount up the disks, like guestfish -i.
    #
    # Sort keys by length, shortest first, so that we end up
    # mounting the filesystems in the correct order.
    my %mps = $g->inspect_get_mountpoints ($root);
    my @mps = sort { length $a <=> length $b } (keys %mps);
    for my $mp (@mps) {
        eval { $g->mount_ro ($mps{$mp}, $mp) };
        if ($@) {
            print "$@ (ignored)\n"
        }
    }

    # If /etc/issue.net file exists, print up to 3 lines.
    my $filename = "/etc/issue.net";
    if ($g->is_file ($filename)) {
        printf "--- %s ---\n", $filename;
        my @lines = $g->head_n (3, $filename);
        print "$_\n" foreach @lines;
    }

    # Unmount everything.
    $g->umount_all ()
}
