--TEST--
Launch, create partitions and LVs and filesystems.
--FILE--
<?php
$g = guestfs_create ();
guestfs_add_drive_scratch ($g, 500 * 1024 * 1024);
guestfs_launch ($g);

guestfs_pvcreate ($g, "/dev/sda");
guestfs_vgcreate ($g, "VG", array ("/dev/sda"));
guestfs_lvcreate ($g, "LV1", "VG", 200);
guestfs_lvcreate ($g, "LV2", "VG", 200);

$lvs = guestfs_lvs ($g);
var_dump ($lvs);

guestfs_mkfs ($g, "ext2", "/dev/VG/LV1");
guestfs_mount ($g, "/dev/VG/LV1", "/");
guestfs_mkdir ($g, "/p");
guestfs_touch ($g, "/q");

function dir_cmp ($a, $b)
{
  return strcmp ($a["name"], $b["name"]);
}
function dir_extract ($n)
{
  return array ("name" => $n["name"], "ftyp" => $n["ftyp"]);
}
$dirs = guestfs_readdir ($g, "/");
usort ($dirs, "dir_cmp");
$dirs = array_map ("dir_extract", $dirs);
var_dump ($dirs);

guestfs_shutdown ($g);
echo ("OK\n");
?>
--EXPECT--
array(2) {
  [0]=>
  string(11) "/dev/VG/LV1"
  [1]=>
  string(11) "/dev/VG/LV2"
}
array(5) {
  [0]=>
  array(2) {
    ["name"]=>
    string(1) "."
    ["ftyp"]=>
    string(1) "d"
  }
  [1]=>
  array(2) {
    ["name"]=>
    string(2) ".."
    ["ftyp"]=>
    string(1) "d"
  }
  [2]=>
  array(2) {
    ["name"]=>
    string(10) "lost+found"
    ["ftyp"]=>
    string(1) "d"
  }
  [3]=>
  array(2) {
    ["name"]=>
    string(1) "p"
    ["ftyp"]=>
    string(1) "d"
  }
  [4]=>
  array(2) {
    ["name"]=>
    string(1) "q"
    ["ftyp"]=>
    string(1) "r"
  }
}
OK
