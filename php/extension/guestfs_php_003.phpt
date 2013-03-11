--TEST--
Check function with optional arguments.
--FILE--
<?php

// See comment in php/run-php-tests.sh.
//putenv ('LIBGUESTFS_DEBUG=1');
if (! $fp = fopen ("env", "r")) {
  die ("Error: cannot open environment file 'env'\n");
}
while (($buffer = fgets ($fp)) != false) {
  putenv (chop ($buffer, "\n"));
}
if (!feof ($fp)) {
  die ("Error: unexpected failure of fgets\n");
}
fclose ($fp);

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
