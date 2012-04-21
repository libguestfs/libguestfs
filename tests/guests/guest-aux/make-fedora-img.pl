#!/usr/bin/perl
# libguestfs
# Copyright (C) 2010-2012 Red Hat Inc.
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

my @images;
my $g = Sys::Guestfs->new ();

my $bootdev;
my $rootdev;

foreach ('LAYOUT', 'SRCDIR') {
  defined ($ENV{$_}) or die "Missing environment variable: $_";
}

if ($ENV{LAYOUT} eq 'partitions') {
  push (@images, "fedora.img.tmp.$$");

  open (my $fstab, '>', "fstab.tmp.$$") or die;
  print $fstab <<EOF;
LABEL=BOOT /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF
  close ($fstab) or die;

  $bootdev = '/dev/sda1';
  $rootdev = '/dev/sda2';

  open (my $img, '>', "fedora.img.tmp.$$") or die;
  truncate ($img, 512*1024*1024) or die;
  close ($img) or die;

  $g->add_drive ("fedora.img.tmp.$$");
  $g->launch ();

  $g->part_init ('/dev/sda', 'mbr');
  $g->part_add ('/dev/sda', 'p', 64, 524287);
  $g->part_add ('/dev/sda', 'p', 524288, -64);
}

elsif ($ENV{LAYOUT} eq 'partitions-md') {
  push (@images, "fedora-md1.img.tmp.$$", "fedora-md2.img.tmp.$$");

  open (my $fstab, '>', "fstab.tmp.$$") or die;
  print $fstab <<EOF;
/dev/md0 /boot ext2 default 0 0
LABEL=ROOT / ext2 default 0 0
EOF
  close ($fstab) or die;

  $bootdev = '/dev/md/boot';
  $rootdev = '/dev/md/root';

  foreach my $img (@images) {
    open (my $fh, '>', $img) or die;
    truncate ($fh, 512*1024*1024) or die;
    close ($fh) or die;

    $g->add_drive ($img);
  }

  $g->launch ();

  # Format the disks.
  foreach ('a', 'b') {
    $g->part_init ("/dev/sd$_", 'mbr');
    $g->part_add ("/dev/sd$_", 'p', 64, 524287);
    $g->part_add ("/dev/sd$_", 'p', 524288, -64);
  }

  $g->md_create ('boot', ['/dev/sda1', '/dev/sdb1']);
  $g->md_create ('root', ['/dev/sda2', '/dev/sdb2']);

  open (my $mdadm, '>', "mdadm.tmp.$$") or die;
  print $mdadm <<EOF;
MAILADDR root
AUTO +imsm +1.x -all
EOF

  my $i = 0;
  foreach ('boot', 'root') {
    my %detail = $g->md_detail ("/dev/md/$_");
    print $mdadm "ARRAY /dev/md$i level=raid1 num-devices=2 UUID=",
                 $detail{uuid}, "\n";
    $i++;
  }

  close ($mdadm) or die;
}

else {
  print STDERR "$0: Unknown LAYOUT: ",$ENV{LAYOUT},"\n";
  exit 1;
}

$g->pvcreate ($rootdev);
$g->vgcreate ('VG', [$rootdev]);
$g->lvcreate ('Root', 'VG', 32);
$g->lvcreate ('LV1', 'VG', 32);
$g->lvcreate ('LV2', 'VG', 32);
$g->lvcreate ('LV3', 'VG', 64);

# Phony /boot filesystem
$g->mkfs_opts ('ext2', $bootdev, blocksize => 4096);
$g->set_e2label ($bootdev, 'BOOT');
$g->set_e2uuid ($bootdev, '01234567-0123-0123-0123-012345678901');

# Phony root filesystem.
$g->mkfs_opts ('ext2', '/dev/VG/Root', blocksize => 4096);
$g->set_e2label ('/dev/VG/Root', 'ROOT');
$g->set_e2uuid ('/dev/VG/Root', '01234567-0123-0123-0123-012345678902');

# Enough to fool inspection API.
$g->mount_options ('', '/dev/VG/Root', '/');
$g->mkdir ('/boot');
$g->mount_options ('', $bootdev, '/boot');
$g->mkdir ('/bin');
$g->mkdir ('/etc');
$g->mkdir ('/etc/sysconfig');
$g->mkdir ('/usr');
$g->mkdir_p ('/var/lib/rpm');

$g->write ('/etc/shadow', "root::15440:0:99999:7:::\n");
$g->chmod (0, '/etc/shadow');
$g->lsetxattr ('security.selinux', "system_u:object_r:shadow_t:s0\0", 30,
               '/etc/shadow');

$g->upload ("fstab.tmp.$$", '/etc/fstab');
$g->write ('/etc/redhat-release', 'Fedora release 14 (Phony)');
$g->write ('/etc/fedora-release', 'Fedora release 14 (Phony)');
$g->write ('/etc/sysconfig/network', 'HOSTNAME=fedora.invalid');

if (-f "mdadm.tmp.$$") {
  $g->upload ("mdadm.tmp.$$", '/etc/mdadm.conf');
  unlink ("mdadm.tmp.$$") or die;
}

$g->upload ('guest-aux/fedora-name.db', '/var/lib/rpm/Name');
$g->upload ('guest-aux/fedora-packages.db', '/var/lib/rpm/Packages');

$g->upload ($ENV{SRCDIR}.'/../data/bin-x86_64-dynamic', '/bin/ls');

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

# Other filesystems.
# Note that these should be empty, for testing virt-df.
$g->mkfs_opts ('ext2', '/dev/VG/LV1', blocksize => 4096);
$g->mkfs_opts ('ext2', '/dev/VG/LV2', blocksize => 1024);
$g->mkfs_opts ('ext2', '/dev/VG/LV3', blocksize => 2048);

# Cleanup
unlink ("fstab.tmp.$$") or die;
foreach my $img (@images) {
  $img =~ /^(.*)\.tmp\.\d+$/ or die;
  rename ($img, $1) or die;
}
