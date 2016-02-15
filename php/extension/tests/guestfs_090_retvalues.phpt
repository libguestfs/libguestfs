--TEST--
Check all the kind of return values.
--FILE--
<?php
$g = guestfs_create ();

# rint
var_dump (guestfs_internal_test_rint ($g, "10"));
var_dump (guestfs_internal_test_rinterr ($g));

# rint64
var_dump (guestfs_internal_test_rint64 ($g, "10"));
var_dump (guestfs_internal_test_rint64err ($g));

# rbool
var_dump (guestfs_internal_test_rbool ($g, "true"));
var_dump (guestfs_internal_test_rbool ($g, "false"));
var_dump (guestfs_internal_test_rboolerr ($g));

# rconststring
var_dump (guestfs_internal_test_rconststring ($g, "test"));
var_dump (guestfs_internal_test_rconststringerr ($g));

# rconstoptstring
var_dump (guestfs_internal_test_rconstoptstring ($g, "test"));
var_dump (guestfs_internal_test_rconstoptstringerr ($g));

# rstring
var_dump (guestfs_internal_test_rstring ($g, "test"));
var_dump (guestfs_internal_test_rstringerr ($g));

# rstringlist
var_dump (guestfs_internal_test_rstringlist ($g, "0"));
var_dump (guestfs_internal_test_rstringlist ($g, "5"));
var_dump (guestfs_internal_test_rstringlisterr ($g));

# rstruct
var_dump (guestfs_internal_test_rstruct ($g, "unused"));
var_dump (guestfs_internal_test_rstructerr ($g));

# rstructlist
var_dump (guestfs_internal_test_rstructlist ($g, "0"));
var_dump (guestfs_internal_test_rstructlist ($g, "5"));
var_dump (guestfs_internal_test_rstructlisterr ($g));

# rhashtable
var_dump (guestfs_internal_test_rhashtable ($g, "0"));
var_dump (guestfs_internal_test_rhashtable ($g, "5"));
var_dump (guestfs_internal_test_rhashtableerr ($g));

# rbufferout
var_dump (guestfs_internal_test_rbufferout ($g, "test"));
var_dump (guestfs_internal_test_rbufferouterr ($g));

echo ("OK\n");
?>
--EXPECT--
int(10)
bool(false)
int(10)
bool(false)
bool(true)
bool(false)
bool(false)
string(13) "static string"
bool(false)
string(13) "static string"
NULL
string(4) "test"
bool(false)
array(0) {
}
array(5) {
  [0]=>
  string(1) "0"
  [1]=>
  string(1) "1"
  [2]=>
  string(1) "2"
  [3]=>
  string(1) "3"
  [4]=>
  string(1) "4"
}
bool(false)
array(14) {
  ["pv_name"]=>
  string(3) "pv0"
  ["pv_uuid"]=>
  string(32) "12345678901234567890123456789012"
  ["pv_fmt"]=>
  string(7) "unknown"
  ["pv_size"]=>
  int(0)
  ["dev_size"]=>
  int(0)
  ["pv_free"]=>
  int(0)
  ["pv_used"]=>
  int(0)
  ["pv_attr"]=>
  string(5) "attr0"
  ["pv_pe_count"]=>
  int(0)
  ["pv_pe_alloc_count"]=>
  int(0)
  ["pv_tags"]=>
  string(4) "tag0"
  ["pe_start"]=>
  int(0)
  ["pv_mda_count"]=>
  int(0)
  ["pv_mda_free"]=>
  int(0)
}
bool(false)
array(0) {
}
array(5) {
  [0]=>
  array(14) {
    ["pv_name"]=>
    string(3) "pv0"
    ["pv_uuid"]=>
    string(32) "12345678901234567890123456789012"
    ["pv_fmt"]=>
    string(7) "unknown"
    ["pv_size"]=>
    int(0)
    ["dev_size"]=>
    int(0)
    ["pv_free"]=>
    int(0)
    ["pv_used"]=>
    int(0)
    ["pv_attr"]=>
    string(5) "attr0"
    ["pv_pe_count"]=>
    int(0)
    ["pv_pe_alloc_count"]=>
    int(0)
    ["pv_tags"]=>
    string(4) "tag0"
    ["pe_start"]=>
    int(0)
    ["pv_mda_count"]=>
    int(0)
    ["pv_mda_free"]=>
    int(0)
  }
  [1]=>
  array(14) {
    ["pv_name"]=>
    string(3) "pv1"
    ["pv_uuid"]=>
    string(32) "12345678901234567890123456789012"
    ["pv_fmt"]=>
    string(7) "unknown"
    ["pv_size"]=>
    int(1)
    ["dev_size"]=>
    int(1)
    ["pv_free"]=>
    int(1)
    ["pv_used"]=>
    int(1)
    ["pv_attr"]=>
    string(5) "attr1"
    ["pv_pe_count"]=>
    int(1)
    ["pv_pe_alloc_count"]=>
    int(1)
    ["pv_tags"]=>
    string(4) "tag1"
    ["pe_start"]=>
    int(1)
    ["pv_mda_count"]=>
    int(1)
    ["pv_mda_free"]=>
    int(1)
  }
  [2]=>
  array(14) {
    ["pv_name"]=>
    string(3) "pv2"
    ["pv_uuid"]=>
    string(32) "12345678901234567890123456789012"
    ["pv_fmt"]=>
    string(7) "unknown"
    ["pv_size"]=>
    int(2)
    ["dev_size"]=>
    int(2)
    ["pv_free"]=>
    int(2)
    ["pv_used"]=>
    int(2)
    ["pv_attr"]=>
    string(5) "attr2"
    ["pv_pe_count"]=>
    int(2)
    ["pv_pe_alloc_count"]=>
    int(2)
    ["pv_tags"]=>
    string(4) "tag2"
    ["pe_start"]=>
    int(2)
    ["pv_mda_count"]=>
    int(2)
    ["pv_mda_free"]=>
    int(2)
  }
  [3]=>
  array(14) {
    ["pv_name"]=>
    string(3) "pv3"
    ["pv_uuid"]=>
    string(32) "12345678901234567890123456789012"
    ["pv_fmt"]=>
    string(7) "unknown"
    ["pv_size"]=>
    int(3)
    ["dev_size"]=>
    int(3)
    ["pv_free"]=>
    int(3)
    ["pv_used"]=>
    int(3)
    ["pv_attr"]=>
    string(5) "attr3"
    ["pv_pe_count"]=>
    int(3)
    ["pv_pe_alloc_count"]=>
    int(3)
    ["pv_tags"]=>
    string(4) "tag3"
    ["pe_start"]=>
    int(3)
    ["pv_mda_count"]=>
    int(3)
    ["pv_mda_free"]=>
    int(3)
  }
  [4]=>
  array(14) {
    ["pv_name"]=>
    string(3) "pv4"
    ["pv_uuid"]=>
    string(32) "12345678901234567890123456789012"
    ["pv_fmt"]=>
    string(7) "unknown"
    ["pv_size"]=>
    int(4)
    ["dev_size"]=>
    int(4)
    ["pv_free"]=>
    int(4)
    ["pv_used"]=>
    int(4)
    ["pv_attr"]=>
    string(5) "attr4"
    ["pv_pe_count"]=>
    int(4)
    ["pv_pe_alloc_count"]=>
    int(4)
    ["pv_tags"]=>
    string(4) "tag4"
    ["pe_start"]=>
    int(4)
    ["pv_mda_count"]=>
    int(4)
    ["pv_mda_free"]=>
    int(4)
  }
}
bool(false)
array(0) {
}
array(5) {
  [0]=>
  string(1) "0"
  [1]=>
  string(1) "1"
  [2]=>
  string(1) "2"
  [3]=>
  string(1) "3"
  [4]=>
  string(1) "4"
}
bool(false)
string(4) "test"
bool(false)
OK
