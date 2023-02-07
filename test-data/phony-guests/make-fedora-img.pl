#!/usr/bin/env perl
# libguestfs
# Copyright (C) 2010-2023 Red Hat Inc.
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

# Make a standard test image which is used by all the tools test
# scripts.  This test image is supposed to look like a Fedora
# installation, or at least enough of one to fool the inspection API
# heuristics.

use strict;
use warnings;

use Sys::Guestfs;
use File::Temp;

my $IMAGE_SIZE = 1024*1024*1024; # bytes
my $LEADING_SECTORS = 64;
my $TRAILING_SECTORS = 64;
my $SECTOR_SIZE = 512; # bytes

my @PARTITIONS = (
    # 32k blank space
    ['p', $LEADING_SECTORS, $IMAGE_SIZE/2/$SECTOR_SIZE-1],
    ['p', $IMAGE_SIZE/2/$SECTOR_SIZE, -$TRAILING_SECTORS],
    # 32k blank space
);

my @images;
my $g = Sys::Guestfs->new ();

my $bootdev;

foreach ('LAYOUT', 'SRCDIR') {
    defined ($ENV{$_}) or die "Missing environment variable: $_";
}

if ($ENV{LAYOUT} eq 'partitions') {
    push (@images, "fedora.img-t");

    open (my $fstab, '>', "fedora.fstab") or die;
    print $fstab <<EOF;
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF
    close ($fstab) or die;

    $bootdev = '/dev/sda1';

    $g->disk_create ("fedora.img-t", "raw", $IMAGE_SIZE);

    $g->add_drive ("fedora.img-t", format => "raw");
    $g->launch ();

    $g->part_init ('/dev/sda', 'mbr');
    foreach my $p (@PARTITIONS) {
        $g->part_add('/dev/sda', @$p);
    }

    init_lvm_root ('/dev/sda2');
}

elsif ($ENV{LAYOUT} eq 'partitions-md') {
    push (@images, "fedora-md1.img-t", "fedora-md2.img-t");

    open (my $fstab, '>', "fedora.fstab") or die;
    print $fstab <<EOF;
/dev/md0 /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF
    close ($fstab) or die;

    $bootdev = '/dev/md/bootdev';

    foreach my $img (@images) {
        $g->disk_create ($img, "raw", $IMAGE_SIZE);
        $g->add_drive ($img, format => "raw");
    }

    $g->launch ();

    # Format the disks.
    foreach my $d ('a', 'b') {
        $g->part_init ("/dev/sd$d", 'mbr');
        foreach my $p (@PARTITIONS) {
            $g->part_add("/dev/sd$d", @$p);
        }
    }

    $g->md_create ('bootdev', ['/dev/sda1', '/dev/sdb1']);
    $g->md_create ('rootdev', ['/dev/sda2', '/dev/sdb2']);

    open (my $mdadm, '>', "fedora.mdadm") or die;
    print $mdadm <<EOF;
MAILADDR root
AUTO +imsm +1.x -all
EOF

    my $i = 0;
    foreach ('bootdev', 'rootdev') {
        my %detail = $g->md_detail ("/dev/md/$_");
        print $mdadm "ARRAY /dev/md$i level=raid1 num-devices=2 UUID=",
            $detail{uuid}, "\n";
        $i++;
    }

    close ($mdadm) or die;

    init_lvm_root ('/dev/md/rootdev');
}

elsif ($ENV{LAYOUT} eq 'btrfs') {
    # Test if btrfs is available.
    my $g2 = Sys::Guestfs->new ();
    $g2->add_drive ("/dev/null");
    $g2->launch ();
    my $btrfs_available = $g2->feature_available (["btrfs"]);
    $g2->close ();

    if (!$btrfs_available) {
        # Btrfs not available, create an empty image.
        push (@images, "fedora-btrfs.img");

        unlink ("fedora-btrfs.img");
        open (my $img, '>', "fedora-btrfs.img");
        close ($img) or die;
        exit 0;
    }
    else {
        push (@images, "fedora-btrfs.img-t");

        open (my $fstab, '>', "fedora.fstab") or die;
        print $fstab <<EOF;
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / btrfs subvol=root 0 0
LABEL=ROOT /home btrfs subvol=home 0 0
EOF
        close ($fstab) or die;

        $bootdev = '/dev/sda1';

        $g->disk_create ("fedora-btrfs.img-t", "raw", $IMAGE_SIZE);

        $g->add_drive ("fedora-btrfs.img-t", format => "raw");
        $g->launch ();

        $g->part_init ('/dev/sda', 'mbr');
        $g->part_add ('/dev/sda', 'p', 64, 524287);
        $g->part_add ('/dev/sda', 'p', 524288, -64);

        $g->mkfs_btrfs (['/dev/sda2'], label => 'ROOT');
        $g->mount ('/dev/sda2', '/');
        $g->btrfs_subvolume_create ('/root');
        $g->btrfs_subvolume_create ('/home');
        $g->umount ('/');

        $g->mount ('btrfsvol:/dev/sda2/root', '/');
    }
}

elsif ($ENV{LAYOUT} eq 'lvm-on-luks') {
    push (@images, "fedora-lvm-on-luks.img-t");

    open (my $fstab, '>', "fedora.fstab") or die;
    print $fstab <<EOF;
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF
    close ($fstab) or die;

    $bootdev = '/dev/sda1';

    $g->disk_create ("fedora-lvm-on-luks.img-t", "raw", $IMAGE_SIZE);

    $g->add_drive ("fedora-lvm-on-luks.img-t", format => "raw");
    $g->launch ();

    $g->part_init ('/dev/sda', 'mbr');
    foreach my $p (@PARTITIONS) {
        $g->part_add('/dev/sda', @$p);
    }

    # Put LUKS on the second partition.
    $g->luks_format ('/dev/sda2', 'FEDORA', 0);
    $g->cryptsetup_open ('/dev/sda2', 'FEDORA', 'luks');

    init_lvm_root ('/dev/mapper/luks');
}

elsif ($ENV{LAYOUT} eq 'luks-on-lvm') {
    push (@images, "fedora-luks-on-lvm.img-t");

    open (my $fstab, '>', "fedora.fstab") or die;
    print $fstab <<EOF;
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF
    close ($fstab) or die;

    $bootdev = '/dev/sda1';

    $g->disk_create ("fedora-luks-on-lvm.img-t", "raw", $IMAGE_SIZE);

    $g->add_drive ("fedora-luks-on-lvm.img-t", format => "raw");
    $g->launch ();

    $g->part_init ('/dev/sda', 'mbr');
    foreach my $p (@PARTITIONS) {
        $g->part_add('/dev/sda', @$p);
    }

    # Create the Volume Group on /dev/sda2.
    $g->pvcreate ('/dev/sda2');
    $g->vgcreate ('VG', ['/dev/sda2']);
    $g->lvcreate ('Root', 'VG', 32);
    $g->lvcreate ('LV1',  'VG', 32);
    $g->lvcreate ('LV2',  'VG', 32);
    $g->lvcreate ('LV3',  'VG', 64);

    # Format each Logical Group as a LUKS device, with a different password.
    $g->luks_format ('/dev/VG/Root', 'FEDORA-Root', 0);
    $g->luks_format ('/dev/VG/LV1',  'FEDORA-LV1',  0);
    $g->luks_format ('/dev/VG/LV2',  'FEDORA-LV2',  0);
    $g->luks_format ('/dev/VG/LV3',  'FEDORA-LV3',  0);

    # Open the LUKS devices. This creates nodes like /dev/mapper/*-luks.
    $g->cryptsetup_open ('/dev/VG/Root', 'FEDORA-Root', 'Root-luks');
    $g->cryptsetup_open ('/dev/VG/LV1',  'FEDORA-LV1',  'LV1-luks');
    $g->cryptsetup_open ('/dev/VG/LV2',  'FEDORA-LV2',  'LV2-luks');
    $g->cryptsetup_open ('/dev/VG/LV3',  'FEDORA-LV3',  'LV3-luks');

    # Phony root filesystem.
    $g->mkfs ('ext2', '/dev/mapper/Root-luks', blocksize => 4096, label => 'ROOT');
    $g->set_uuid ('/dev/mapper/Root-luks', '01234567-0123-0123-0123-012345678902');

    # Other filesystems, just for testing findfs-label.
    $g->mkfs ('ext2', '/dev/mapper/LV1-luks', blocksize => 4096, label => 'LV1');
    $g->mkfs ('ext2', '/dev/mapper/LV2-luks', blocksize => 1024, label => 'LV2');
    $g->mkfs ('ext2', '/dev/mapper/LV3-luks', blocksize => 2048, label => 'LV3');

    $g->mount ('/dev/mapper/Root-luks', '/');
}

else {
    print STDERR "$0: Unknown LAYOUT: ",$ENV{LAYOUT},"\n";
    exit 1;
}

sub init_lvm_root {
    my ($rootdev) = @_;

    $g->pvcreate ($rootdev);
    $g->vgcreate ('VG', [$rootdev]);
    $g->lvcreate ('Root', 'VG', 32);
    $g->lvcreate ('LV1', 'VG', 32);
    $g->lvcreate ('LV2', 'VG', 32);
    $g->lvcreate ('LV3', 'VG', 64);

    # Phony root filesystem.
    $g->mkfs ('ext2', '/dev/VG/Root', blocksize => 4096);
    $g->set_label ('/dev/VG/Root', 'ROOT');
    $g->set_uuid ('/dev/VG/Root', '01234567-0123-0123-0123-012345678902');

    # Other filesystems.
    # Note that these should be empty, for testing virt-df.
    $g->mkfs ('ext2', '/dev/VG/LV1', blocksize => 4096);
    $g->mkfs ('ext2', '/dev/VG/LV2', blocksize => 1024);
    $g->mkfs ('ext2', '/dev/VG/LV3', blocksize => 2048);

    $g->mount ('/dev/VG/Root', '/');
}

# Phony /boot filesystem
$g->mkfs ('ext2', $bootdev, blocksize => 4096);
$g->set_label ($bootdev, 'BOOT');
$g->set_uuid ($bootdev, '01234567-0123-0123-0123-012345678901');

# Enough to fool inspection API.
$g->mkdir ('/boot');
$g->mount ($bootdev, '/boot');
$g->mkdir ('/bin');
$g->mkdir ('/etc');
$g->mkdir ('/etc/sysconfig');
$g->mkdir ('/usr');
$g->mkdir ('/usr/share');
$g->mkdir ('/usr/share/zoneinfo');
$g->mkdir ('/usr/share/zoneinfo/Europe');
$g->touch ('/usr/share/zoneinfo/Europe/London');
$g->mkdir_p ('/var/lib/rpm');
$g->mkdir_p ('/usr/lib/rpm');
$g->mkdir_p ('/var/log/journal');

$g->write ('/etc/shadow', "root::15440:0:99999:7:::\n");
$g->chmod (0, '/etc/shadow');
$g->lsetxattr ('security.selinux', "system_u:object_r:shadow_t:s0\0", 30,
               '/etc/shadow');

$g->upload ("fedora.fstab", '/etc/fstab');
$g->write ('/etc/motd', "Welcome to Fedora release 14 (Phony)\n");
$g->write ('/etc/redhat-release', 'Fedora release 14 (Phony)');
$g->write ('/etc/fedora-release', 'Fedora release 14 (Phony)');
$g->write ('/etc/sysconfig/network', 'HOSTNAME=fedora.invalid');

if (-f "fedora.mdadm") {
    $g->upload ("fedora.mdadm", '/etc/mdadm.conf');
    unlink ("fedora.mdadm") or die;
}

$g->upload ($ENV{SRCDIR}.'/fedora.db', '/var/lib/rpm/rpmdb.sqlite');
$g->touch ('/usr/lib/rpm/rpmrc');
$g->write ('/usr/lib/rpm/macros', <<EOF);
%_dbpath /var/lib/rpm
%_db_backend sqlite
EOF

$g->upload ($ENV{SRCDIR}.'/../binaries/bin-x86_64-dynamic', '/bin/ls');

$g->tar_in ($ENV{SRCDIR}.'/fedora-journal.tar.xz', '/var/log/journal', compress => "xz");

$g->mkdir ('/boot/grub');
$g->touch ('/boot/grub/grub.conf');

# Test files.
$g->write ('/etc/test1', 'abcdefg');
$g->write ('/etc/test2', '');
$g->write ('/etc/test3',
'a
b
c
d
e
f
');
$g->chown (10, 11, '/etc/test3');
$g->chmod (0600, '/etc/test3');
$g->write ('/bin/test1', 'abcdefg');
$g->write ('/bin/test2', 'zxcvbnm');
$g->write ('/bin/test3', '1234567');
$g->write ('/bin/test4', '');
$g->ln_s ('/bin/test1', '/bin/test5');
$g->mkfifo (0777, '/bin/test6');
$g->mknod (0777, 10, 10, '/bin/test7');

# Cleanup
$g->shutdown ();
$g->close ();

unlink ("fedora.fstab") or die;
foreach my $img (@images) {
    $img =~ /^(.*)-t$/ or die;
    rename ($img, $1) or die;
}
