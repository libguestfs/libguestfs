--TEST--
Check the result of guestfs_version().
--FILE--
<?php
$g = guestfs_create ();

$version = guestfs_version ($g);
echo (gettype ($version["major"]) . "\n");
echo (gettype ($version["minor"]) . "\n");
echo (gettype ($version["release"]) . "\n");
echo (gettype ($version["extra"]) . "\n");

echo ("OK\n");
?>
--EXPECT--
integer
integer
integer
string
OK
