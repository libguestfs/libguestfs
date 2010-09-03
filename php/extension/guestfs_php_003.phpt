--TEST--
Create a disk containing LV and filesystem.
--FILE--
<?php

// See comment in php/run-php-tests.sh.
//putenv ('LIBGUESTFS_DEBUG=1');

$g = guestfs_create ();
if ($g == false) {
  die ("Failed to create guestfs_php handle.\n");
}

$tmp = dirname(__FILE__)."/test.img";
$size = 100 * 1024 * 1024;
if (! $fp = fopen ($tmp, 'r+')) {
  die ("Error: cannot create file '".$tmp."'\n");
}
ftruncate ($fp, $size);
fclose ($fp);

if (! guestfs_add_drive ($g, "test.img") ||
    ! guestfs_launch ($g) ||
    ! guestfs_part_disk ($g, "/dev/sda", "mbr") ||
    ! guestfs_pvcreate ($g, "/dev/sda") ||
    ! guestfs_vgcreate ($g, "VG", array ("/dev/sda")) ||
    ! guestfs_lvcreate ($g, "LV", "VG", 64) ||
    ! guestfs_mkfs ($g, "ext2", "/dev/VG/LV")) {
  die ("Error: ".guestfs_last_error ($g)."\n");
}
echo ("OK\n");
?>
--CLEAN--
<?php
$tmp = dirname(__FILE__)."/test.img";
unlink ($tmp);
?>
--EXPECT--
OK
