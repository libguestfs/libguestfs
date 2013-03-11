--TEST--
Load the module and create a handle.
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
echo ("Created guestfs_php handle.\n");
?>
--EXPECT--
Created guestfs_php handle.
