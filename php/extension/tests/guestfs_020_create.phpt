--TEST--
Load the module and create a handle.
--FILE--
<?php
$g = guestfs_create ();
if ($g == false) {
  echo ("Failed to create guestfs_php handle.\n");
  exit;
}
echo ("Created guestfs_php handle.\n");
?>
--EXPECT--
Created guestfs_php handle.
