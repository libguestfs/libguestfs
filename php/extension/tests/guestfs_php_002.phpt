--TEST--
Launch the appliance and run basic tests.
--FILE--
<?php
$g = guestfs_create ();
if ($g == false) {
  echo ("Failed to create guestfs_php handle.\n");
  exit;
}

if (! guestfs_add_drive_scratch ($g, 100 * 1024 * 1024) ||
    ! guestfs_launch ($g) ||
    ! guestfs_part_disk ($g, "/dev/sda", "mbr") ||
    ! guestfs_pvcreate ($g, "/dev/sda1") ||
    ! guestfs_vgcreate ($g, "VG", array ("/dev/sda1")) ||
    ! guestfs_lvcreate ($g, "LV", "VG", 64) ||
    ! guestfs_mkfs ($g, "ext2", "/dev/VG/LV")) {
  die ("Error: ".guestfs_last_error ($g)."\n");
}

$version = guestfs_version ($g);
if ($version == false) {
  echo ("Error: ".guestfs_last_error ($g)."\n");
  exit;
}
if (!is_int ($version["major"]) ||
    !is_int ($version["minor"]) ||
    !is_int ($version["release"]) ||
    !is_string ($version["extra"])) {
  echo ("Error: incorrect return type from guestfs_version\n");
}

echo ("OK\n");
?>
--EXPECT--
OK
