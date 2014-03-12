--TEST--
Check function with optional arguments.
--FILE--
<?php
$g = guestfs_create ();
if ($g == false) {
  echo ("Failed to create guestfs_php handle.\n");
  exit;
}
if (guestfs_add_drive ($g, "/dev/null") == false) {
  echo ("Failed add_drive, no optional arguments: " . guestfs_last_error ($g) . "\n");
  exit;
}
if (guestfs_add_drive ($g, "/dev/null", 0) == false) {
  echo ("Failed add_drive, one optional argument: " . guestfs_last_error ($g) . "\n");
  exit;
}
if (guestfs_add_drive ($g, "/dev/null", 1) == false) {
  echo ("Failed add_drive, one optional argument: " . guestfs_last_error ($g) . "\n");
  exit;
}
if (guestfs_add_drive ($g, "/dev/null", 1, "raw") == false) {
  echo ("Failed add_drive, two optional arguments: " . guestfs_last_error ($g) . "\n");
  exit;
}
echo ("Completed tests OK.\n");
?>
--EXPECT--
Completed tests OK.
