--TEST--
Launch the appliance.
--FILE--
<?php

// See comment in php/run-php-tests.sh.
//putenv ('LIBGUESTFS_DEBUG=1');

$g = guestfs_create ();
if ($g == false) {
  echo ("Failed to create guestfs_php handle.\n");
  exit;
}
if (guestfs_add_drive ($g, "/dev/null") == false) {
  echo ("Error: ".guestfs_last_error ($g)."\n");
  exit;
}
if (guestfs_launch ($g) == false) {
  echo ("Error: ".guestfs_last_error ($g)."\n");
  exit;
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
