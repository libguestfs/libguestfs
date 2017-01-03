#!/usr/bin/env perl
# Copyright (C) 2010-2017 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Stochastic testing of virt-resize.

use strict;
use warnings;

use Getopt::Long;

use Sys::Guestfs;

if ($ENV{SKIP_TEST_VIRT_RESIZE_PL}) {
    print "$0: test skipped because environment variable is set\n";
    exit 77
}

# So srand returns the seed.
if ($] < 5.014) {
    print "$0: test skipped because perl < 5.14\n";
    exit 77
}

# Byte calculations go screwy on 32 bit.
if (~1 == 4294967294) {
    print "$0: this program does not work on a 32 bit host\n";
    exit 77
}

# Command line arguments.
my $help = 0;
my $seed = 0;
GetOptions ("help|?" => \$help,
            "seed=i" => \$seed);
if ($help) {
    print "$0 [--seed=SEED]\n";
    print "  --seed=SEED       Set the starting seed (to reproduce a test)\n";
    exit 0
}

if ($seed == 0) {
    # Choose a random seed.
    $seed = srand ();
}
else {
    # User specified --seed option.
    srand ($seed);
}

$| = 1;

my $g = Sys::Guestfs->new ();
my $backend = $g->get_backend ();

# Choose a random test.
my $part_type = "mbr";
if (rand () <= 0.5) {
    $part_type = "gpt"
}
# If $nr_parts >= 4 && $part_type = "mbr" then this implies creating
# an extended partition (#4) and zero or more logical partitions.
my $nr_parts = 1 + int (rand (7));

# XXX Temporarily restriction XXX
# Currently virt-resize is broken when dealing with any extended
# partition, so don't test this for the moment.
if ($part_type eq "mbr" && $nr_parts >= 4) {
    $nr_parts = 3;
}

# expand (1) or shrink (0)
my $expand = 0;
if (rand () >= 0.2) {
    $expand = 1;
}
my $source_format = "raw";
if ($backend ne "uml" && rand () < 0.2) {
    $source_format = "qcow2";
}
my $target_format = "raw";
if ($backend ne "uml" && rand () < 0.2) {
    $target_format = "qcow2";
}
my $no_extra_partition = 0;
if ($part_type eq "mbr" && $nr_parts > 3) {
    $no_extra_partition = 1;
}
if ($expand && rand () < 0.5) {
    $no_extra_partition = 1;
}

# Print the test before starting, so it will appear in failure output.
print "seed:           $seed\n";
print "partition type: $part_type\n";
print "nr partitions:  $nr_parts\n";
print "expand:         $expand\n";
print "no extra part:  $no_extra_partition\n";
print "source format:  $source_format\n";
print "target format:  $target_format\n";

# Make a structure for each partition, recording what it will contain
# and whether we will --resize / --expand / --shrink it.
# Note this array is numbered from 1!
my @parts;
my $i;
for ($i = 1; $i <= $nr_parts; ++$i) {
    $parts[$i] = { name => "sda".$i, resize => 0 };

    if ($part_type eq "mbr") {
        if ($i < 4) {
            if (rand () < 0.5) {
                $parts[$i]->{resize} = 1;
            }
        } elsif ($i == 4) {
            $parts[$i]->{content} = "extended";
        }
    } else {
        if (rand () < 0.5) {
            $parts[$i]->{resize} = 1;
        }
    }
}

# Pick a partition at random to expand or shrink.
if ($part_type eq "mbr") {
    # virt-resize cannot shrink extended or logical partitions, so we
    # set $max so that these cannot be chosen:
    my $max = 3;
    $max = $nr_parts if $max > $nr_parts;
    $i = 1 + int (rand ($max));
} else {
    $i = 1 + int (rand ($nr_parts));
}
$parts[$i]->{resize} = 0;
$parts[$i]->{expand_shrink} = 1;

# Size of the source disk.  It's always roughly nr_parts * size of
# each partition + a bit extra.  For btrfs we have to choose a large
# partition size.
my $source_size = (10 + $nr_parts * 512) * 1024 * 1024;

# Create the source disk.
my $source_file = "test-virt-resize-source.img";
$g->disk_create ($source_file, $source_format, $source_size);
$g->add_drive ($source_file, format => $source_format);
$g->launch ();

# After launching we can detect if various filesystem types are
# supported and use that to further parameterize the test.
my $vfs_type = "ext2";
my $r = rand ();
if ($r < 0.15) {
    $vfs_type = "lvm";
} elsif ($r < 0.30) {
    if ($g->feature_available (["ntfs3g", "ntfsprogs"])) {
        $vfs_type = "ntfs"
    }
} elsif ($r < 0.45) {
    if ($g->filesystem_available ("btrfs")) {
        $vfs_type = "btrfs"
    }
} elsif ($r < 0.60) {
    # XFS cannot shrink.
    if ($expand && $g->filesystem_available ("xfs")) {
        $vfs_type = "xfs"
    }
}

print "filesystem:     $vfs_type\n";

my $lv_expand = "";
if ($vfs_type eq "lvm" && $expand && rand () < 0.5) {
    $lv_expand = "/dev/VG/LV";
}
print "LV expand:      $lv_expand\n";

for ($i = 1; $i <= $nr_parts; ++$i) {
    $parts[$i]->{content} = $vfs_type unless exists $parts[$i]->{content};
}

for ($i = 1; $i <= $nr_parts; ++$i) {
    printf "partition %d:    %s %s ", $i, $parts[$i]->{name}, $parts[$i]->{content};
    if ($parts[$i]->{resize}) {
        print "resize"
    } elsif ($parts[$i]->{expand_shrink}) {
        if ($expand) {
            print "expand"
        }
        else {
            print "shrink"
        }
    } else {
        print "-";
    }
    print "\n";
}

# Create the source disk partitions.
$g->part_init ("/dev/sda", $part_type);
my $start = 2048;

if ($part_type eq "gpt") {
    for (my $i = 1; $i <= $nr_parts; ++$i) {
        my $end = $start + 1024*1024 - 1;
        $g->part_add ("/dev/sda", "primary", $start, $end);
        $start = $end+1;
    }
} else {
    # MBR is nuts ...
    for ($i = 1; $i <= $nr_parts; ++$i) {
        if ($i <= 3) {
            my $end = $start + 1024*1024 - 1;
            $g->part_add ("/dev/sda", "primary", $start, $end);
            $start = $end+1;
        }
        elsif ($i == 4) {
            # Extended partition is a container, so it just stretches
            # to the end of the disk.
            $g->part_add ("/dev/sda", "extended", $start, -2048);
            $start += 1024;
        }
        else {
            # Logical partitions sit inside the container, but the
            # confusing thing about them is we have to take into
            # account the sector that contains the linked list of
            # logical partitions, hence -2/+2 below.
            my $end = $start + 1024*1024 - 2;
            $g->part_add ("/dev/sda", "logical", $start, $end);
            $start = $end+2;
        }
    }
}

# Create the filesystem content.
for ($i = 1; $i <= $nr_parts; ++$i) {
    my $dev = "/dev/" . $parts[$i]->{name};
    my $content = $parts[$i]->{content};
    if ($content eq "extended") {
        # do nothing - it's the extended partition
    } elsif ($content eq "lvm") {
        $g->pvcreate ($dev);
        # If shrinking, shrink the PV to < 260MB.
        if (!$expand) {
            $g->pvresize_size ($dev, 256 * 1024 * 1024);
        }
    } else {
        $g->mkfs ($content, $dev);
        # If shrinking, shrink the filesystem to < 260MB.
        if (!$expand) {
            if ($content eq "ext2") {
                $g->resize2fs_size ($dev, 256 * 1024 * 1024);
            } elsif ($content eq "btrfs") {
                $g->mount ($dev, "/");
                $g->btrfs_filesystem_resize ("/", size => 256 * 1024 * 1024);
                $g->umount_all ();
            } elsif ($content eq "ntfs") {
                $g->ntfsresize ($dev, size => 256 * 1024 * 1024);
            } else {
                die "internal error: content = $content";
            }
        }
    }
}

# For LVM, create the LV.
if ($vfs_type eq "lvm") {
    my @pvs = $g->pvs ();
    $g->vgcreate ("VG", \@pvs);
    $g->lvcreate ("LV", "VG", 256);
    $g->mkfs ("ext2", "/dev/VG/LV");
}

# Close the source.
$g->shutdown ();
$g->close ();

# What size should the target be?  It depends on how many partitions
# will be resized.
my $target_size = 0;
for ($i = 1; $i <= $nr_parts; ++$i) {
    if ($parts[$i]->{resize} || $parts[$i]->{expand_shrink}) {
        if ($expand) {
            $target_size += 800;
        } else {
            $target_size += 260;
        }
    } else {
        $target_size += 512; # remain at original size
    }
}
$target_size += 10;
$target_size *= 1024 * 1024;

# Create the empty target container.
my $target_file = "test-virt-resize-target.img";
Sys::Guestfs->new ()->disk_create ($target_file, $target_format, $target_size);

# Create the virt-resize command.
my @command = (
    "virt-resize",
    "--format", $source_format,
    "--output-format", $target_format,
    );

if ($vfs_type eq "ntfs") {
    push @command, "--ntfsresize-force"
}

for ($i = 1; $i <= $nr_parts; ++$i) {
    my $dev = "/dev/" . $parts[$i]->{name};
    if ($expand) {
        if ($parts[$i]->{resize}) {
            push @command, "--resize", $dev."=+256M";
        } else {
            if ($parts[$i]->{expand_shrink}) {
                push @command, "--expand", $dev;
            }
        }
    } else { # shrink
        if ($parts[$i]->{resize}) {
            push @command, "--resize", $dev."=-256M";
        } else {
            if ($parts[$i]->{expand_shrink}) {
                push @command, "--shrink", $dev;
            }
        }
    }
}

if ($lv_expand) {
    push @command, "--lvexpand", $lv_expand
}

if ($no_extra_partition) {
    push @command, "--no-extra-partition"
}

push @command, $source_file, $target_file;

print (join(" ", @command), "\n");

system (@command) == 0 or die "command: '@command' failed: $?\n";

# Clean up.
unlink $source_file;
unlink $target_file;

exit 0
