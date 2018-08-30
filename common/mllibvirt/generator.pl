#!/usr/bin/perl -w
#
# OCaml bindings for libvirt.
# (C) Copyright 2007-2015 Richard W.M. Jones, Red Hat Inc.
# https://libvirt.org/
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version,
# with the OCaml linking exception described in ../COPYING.LIB.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

# This generates libvirt_c.c (the core of the bindings).  You don't
# need to run this program unless you are extending the bindings
# themselves (eg. because libvirt has been extended).
#
# Please read libvirt/README.

use strict;

#----------------------------------------------------------------------

# The functions in the libvirt API that we can generate.

# The 'sig' (signature) doesn't have a meaning or any internal structure.
# It is interpreted by the generation functions below to indicate what
# "class" the function falls into, and to generate the right class of
# binding.

my @functions = (
    { name => "virConnectClose", sig => "conn : free" },
    { name => "virConnectGetHostname", sig => "conn : string" },
    { name => "virConnectGetURI", sig => "conn : string" },
    { name => "virConnectGetType", sig => "conn : static string" },
    { name => "virConnectNumOfDomains", sig => "conn : int" },
    { name => "virConnectListDomains", sig => "conn, int : int array" },
    { name => "virConnectNumOfDefinedDomains", sig => "conn : int" },
    { name => "virConnectListDefinedDomains",
      sig => "conn, int : string array" },
    { name => "virConnectNumOfNetworks", sig => "conn : int" },
    { name => "virConnectListNetworks", sig => "conn, int : string array" },
    { name => "virConnectNumOfDefinedNetworks", sig => "conn : int" },
    { name => "virConnectListDefinedNetworks",
      sig => "conn, int : string array" },
    { name => "virConnectNumOfStoragePools", sig => "conn : int" },
    { name => "virConnectListStoragePools",
      sig => "conn, int : string array" },
    { name => "virConnectNumOfDefinedStoragePools",
      sig => "conn : int" },
    { name => "virConnectListDefinedStoragePools",
      sig => "conn, int : string array" },
    { name => "virConnectNumOfSecrets", sig => "conn : int" },
    { name => "virConnectListSecrets", sig => "conn, int : string array" },
    { name => "virConnectGetCapabilities", sig => "conn : string" },
    { name => "virConnectDomainEventDeregisterAny",
      sig => "conn, int : unit" },

    { name => "virDomainCreateLinux", sig => "conn, string, 0U : dom" },
    { name => "virDomainCreateXML", sig => "conn, string, unsigned : dom" },
    { name => "virDomainFree", sig => "dom : free" },
    { name => "virDomainDestroy", sig => "dom : free" },
    { name => "virDomainLookupByName", sig => "conn, string : dom" },
    { name => "virDomainLookupByID", sig => "conn, int : dom" },
    { name => "virDomainLookupByUUID", sig => "conn, uuid : dom" },
    { name => "virDomainLookupByUUIDString", sig => "conn, string : dom" },
    { name => "virDomainGetName", sig => "dom : static string" },
    { name => "virDomainGetOSType", sig => "dom : string" },
    { name => "virDomainGetXMLDesc", sig => "dom, 0 : string" },
    { name => "virDomainGetUUID", sig => "dom : uuid" },
    { name => "virDomainGetUUIDString", sig => "dom : uuid string" },
    { name => "virDomainGetMaxVcpus", sig => "dom : int" },
    { name => "virDomainSave", sig => "dom, string : unit" },
    { name => "virDomainRestore", sig => "conn, string : unit" },
    { name => "virDomainCoreDump", sig => "dom, string, 0 : unit" },
    { name => "virDomainSuspend", sig => "dom : unit" },
    { name => "virDomainResume", sig => "dom : unit" },
    { name => "virDomainShutdown", sig => "dom : unit" },
    { name => "virDomainReboot", sig => "dom, 0 : unit" },
    { name => "virDomainDefineXML", sig => "conn, string : dom" },
    { name => "virDomainUndefine", sig => "dom : unit" },
    { name => "virDomainCreate", sig => "dom : unit" },
    { name => "virDomainAttachDevice", sig => "dom, string : unit" },
    { name => "virDomainDetachDevice", sig => "dom, string : unit" },
    { name => "virDomainGetAutostart", sig => "dom : bool" },
    { name => "virDomainSetAutostart", sig => "dom, bool : unit" },

    { name => "virNetworkFree", sig => "net : free" },
    { name => "virNetworkDestroy", sig => "net : free" },
    { name => "virNetworkLookupByName", sig => "conn, string : net" },
    { name => "virNetworkLookupByUUID", sig => "conn, uuid : net" },
    { name => "virNetworkLookupByUUIDString", sig => "conn, string : net" },
    { name => "virNetworkGetName", sig => "net : static string" },
    { name => "virNetworkGetXMLDesc", sig => "net, 0 : string" },
    { name => "virNetworkGetBridgeName", sig => "net : string" },
    { name => "virNetworkGetUUID", sig => "net : uuid" },
    { name => "virNetworkGetUUIDString", sig => "net : uuid string" },
    { name => "virNetworkUndefine", sig => "net : unit" },
    { name => "virNetworkCreateXML", sig => "conn, string : net" },
    { name => "virNetworkDefineXML", sig => "conn, string : net" },
    { name => "virNetworkCreate", sig => "net : unit" },
    { name => "virNetworkGetAutostart", sig => "net : bool" },
    { name => "virNetworkSetAutostart", sig => "net, bool : unit" },

    { name => "virStoragePoolFree", sig => "pool : free" },
    { name => "virStoragePoolDestroy", sig => "pool : free" },
    { name => "virStoragePoolLookupByName",
      sig => "conn, string : pool" },
    { name => "virStoragePoolLookupByUUID",
      sig => "conn, uuid : pool" },
    { name => "virStoragePoolLookupByUUIDString",
      sig => "conn, string : pool" },
    { name => "virStoragePoolGetName",
      sig => "pool : static string" },
    { name => "virStoragePoolGetXMLDesc",
      sig => "pool, 0U : string" },
    { name => "virStoragePoolGetUUID",
      sig => "pool : uuid" },
    { name => "virStoragePoolGetUUIDString",
      sig => "pool : uuid string" },
    { name => "virStoragePoolCreateXML",
      sig => "conn, string, 0U : pool" },
    { name => "virStoragePoolDefineXML",
      sig => "conn, string, 0U : pool" },
    { name => "virStoragePoolBuild",
      sig => "pool, uint : unit" },
    { name => "virStoragePoolUndefine",
      sig => "pool : unit" },
    { name => "virStoragePoolCreate",
      sig => "pool, 0U : unit" },
    { name => "virStoragePoolDelete",
      sig => "pool, uint : unit" },
    { name => "virStoragePoolRefresh",
      sig => "pool, 0U : unit" },
    { name => "virStoragePoolGetAutostart",
      sig => "pool : bool" },
    { name => "virStoragePoolSetAutostart",
      sig => "pool, bool : unit" },
    { name => "virStoragePoolNumOfVolumes",
      sig => "pool : int" },
    { name => "virStoragePoolListVolumes",
      sig => "pool, int : string array" },

    { name => "virStorageVolFree", sig => "vol : free" },
    { name => "virStorageVolDelete",
      sig => "vol, uint : unit" },
    { name => "virStorageVolLookupByName",
      sig => "pool, string : vol from pool" },
    { name => "virStorageVolLookupByKey",
      sig => "conn, string : vol" },
    { name => "virStorageVolLookupByPath",
      sig => "conn, string : vol" },
    { name => "virStorageVolCreateXML",
      sig => "pool, string, 0U : vol from pool" },
    { name => "virStorageVolGetXMLDesc",
      sig => "vol, 0U : string" },
    { name => "virStorageVolGetPath",
      sig => "vol : string" },
    { name => "virStorageVolGetKey",
      sig => "vol : static string" },
    { name => "virStorageVolGetName",
      sig => "vol : static string" },
    { name => "virStoragePoolLookupByVolume",
      sig => "vol : pool from vol" },

    { name => "virSecretFree", sig => "sec : free" },
    { name => "virSecretUndefine", sig => "sec : unit" },
    { name => "virSecretLookupByUUID", sig => "conn, uuid : sec" },
    { name => "virSecretLookupByUUIDString", sig => "conn, string : sec" },
    { name => "virSecretDefineXML", sig => "conn, string, 0 : sec" },
    { name => "virSecretGetUUID", sig => "sec : uuid" },
    { name => "virSecretGetUUIDString", sig => "sec : uuid string" },
    { name => "virSecretGetUsageType", sig => "sec : int" },
    { name => "virSecretGetUsageID", sig => "sec : static string" },
    { name => "virSecretGetXMLDesc", sig => "sec, 0 : string" },

    );

# Functions we haven't implemented anywhere yet but which are mentioned
# in 'libvirt.ml'.
#
# We create stubs for these, but eventually they need to either be
# moved ^^^ so they are auto-generated, or implementations of them
# written in 'libvirt_c_oneoffs.c'.

my @unimplemented = (
    );

#----------------------------------------------------------------------

# Open the output file.

my $filename = "libvirt_c.c";
open F, ">$filename" or die "$filename: $!";

# Write the prologue.

print F <<'END';
/* !!! WARNING WARNING WARNING WARNING WARNING WARNING WARNING !!!
 *
 * THIS FILE IS AUTOMATICALLY GENERATED BY 'generator.pl'.
 *
 * Any changes you make to this file may be overwritten.
 */

/* OCaml bindings for libvirt.
 * (C) Copyright 2007-2015 Richard W.M. Jones, Red Hat Inc.
 * https://libvirt.org/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version,
 * with the OCaml linking exception described in ../COPYING.LIB.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 */

#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>

#include <caml/config.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/misc.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>

#include "libvirt_c_prologue.c"

#include "libvirt_c_oneoffs.c"

END

#----------------------------------------------------------------------

sub camel_case_to_underscores
{
    my $name = shift;

    $name =~ s/([A-Z][a-z]+|XML|URI|OS|UUID)/$1,/g;
    my @subs = split (/,/, $name);
    @subs = map { lc($_) } @subs;
    join "_", @subs
}

# Helper functions dealing with signatures.

sub short_name_to_c_type
{
    local $_ = shift;

    if ($_ eq "conn") { "virConnectPtr" }
    elsif ($_ eq "dom") { "virDomainPtr" }
    elsif ($_ eq "net") { "virNetworkPtr" }
    elsif ($_ eq "pool") { "virStoragePoolPtr" }
    elsif ($_ eq "vol") { "virStorageVolPtr" }
    elsif ($_ eq "sec") { "virSecretPtr" }
    else {
	die "unknown short name $_"
    }
}

# OCaml argument names.

sub gen_arg_names
{
    my $sig = shift;

    if ($sig =~ /^(\w+) : string$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : static string$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : int$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : uuid$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : uuid string$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : bool$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+), bool : unit$/) {
	( "$1v", "bv" )
    } elsif ($sig eq "conn, int : int array") {
	( "connv", "iv" )
    } elsif ($sig =~ /^(\w+), int : string array$/) {
	( "$1v", "iv" )
    } elsif ($sig =~ /^(\w+), 0U? : string$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+), 0U? : unit$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : unit$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : free$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+), string : unit$/) {
	( "$1v", "strv" )
    } elsif ($sig =~ /^(\w+), string, 0U? : unit$/) {
	( "$1v", "strv" )
    } elsif ($sig =~ /^(\w+), string : (\w+)$/) {
	( "$1v", "strv" )
    } elsif ($sig =~ /^(\w+), string, 0U? : (\w+)$/) {
	( "$1v", "strv" )
    } elsif ($sig =~ /^(\w+), string, unsigned : (\w+)$/) {
	( "$1v", "strv", "uv" )
    } elsif ($sig =~ /^(\w+), u?int : (\w+)$/) {
	( "$1v", "iv" )
    } elsif ($sig =~ /^(\w+), uuid : (\w+)$/) {
	( "$1v", "uuidv" )
    } elsif ($sig =~ /^(\w+), 0U? : (\w+)$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : (\w+)$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+), string : (\w+) from \w+$/) {
	( "$1v", "strv" )
    } elsif ($sig =~ /^(\w+), string, 0U? : (\w+) from \w+$/) {
	( "$1v", "strv" )
    } elsif ($sig =~ /^(\w+), 0U? : (\w+) from \w+$/) {
	( "$1v" )
    } elsif ($sig =~ /^(\w+) : (\w+) from \w+$/) {
	( "$1v" )
    } else {
	die "unknown signature $sig"
    }
}

# Unpack the first (object) argument.

sub gen_unpack_args
{
    local $_ = shift;

    if ($_ eq "conn") {
	"virConnectPtr conn = Connect_val (connv);"
    } elsif ($_ eq "dom") {
	"virDomainPtr dom = Domain_val (domv);"
    } elsif ($_ eq "net") {
	"virNetworkPtr net = Network_val (netv);"
    } elsif ($_ eq "pool") {
	"virStoragePoolPtr pool = Pool_val (poolv);"
    } elsif ($_ eq "vol") {
	"virStorageVolPtr vol = Volume_val (volv);"
    } elsif ($_ eq "sec") {
	"virSecretPtr sec = Secret_val (secv);"
    } else {
	die "unknown short name $_"
    }
}

# Pack the result if it's an object.

sub gen_pack_result
{
    local $_ = shift;

    if ($_ eq "dom") {     "rv = Val_domain (r, connv);" }
    elsif ($_ eq "net") {  "rv = Val_network (r, connv);" }
    elsif ($_ eq "pool") { "rv = Val_pool (r, connv);" }
    elsif ($_ eq "vol") {  "rv = Val_volume (r, connv);" }
    elsif ($_ eq "sec") {  "rv = Val_secret (r, connv);" }
    else {
	die "unknown short name $_"
    }
}

sub gen_free_arg
{
    local $_ = shift;

    if ($_ eq "conn") {     "Connect_val (connv) = NULL;" }
    elsif ($_ eq "dom") {   "Domain_val (domv) = NULL;" }
    elsif ($_ eq "net") {   "Network_val (netv) = NULL;" }
    elsif ($_ eq "pool") {  "Pool_val (poolv) = NULL;" }
    elsif ($_ eq "vol") {   "Volume_val (volv) = NULL;" }
    elsif ($_ eq "sec") {   "Secret_val (secv) = NULL;" }
    else {
	die "unknown short name $_"
    }
}

# Generate the C body for each signature (class of function).

sub gen_c_code
{
    my $sig = shift;
    my $c_name = shift;

    if ($sig =~ /^(\w+) : string$/) {
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char *r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (!r, \"$c_name\");

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+) : static string$/) {
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  const char *r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (!r, \"$c_name\");

  rv = caml_copy_string (r);
  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+) : int$/) {
	"\
  " . gen_unpack_args ($1) . "
  int r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (Val_int (r));
"
    } elsif ($sig =~ /^(\w+) : uuid$/) {
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  unsigned char uuid[VIR_UUID_BUFLEN];
  int r;

  NONBLOCKING (r = $c_name ($1, uuid));
  CHECK_ERROR (r == -1, \"$c_name\");

  /* UUIDs are byte arrays with a fixed length. */
  rv = caml_alloc_string (VIR_UUID_BUFLEN);
  memcpy (String_val (rv), uuid, VIR_UUID_BUFLEN);
  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+) : uuid string$/) {
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char uuid[VIR_UUID_STRING_BUFLEN];
  int r;

  NONBLOCKING (r = $c_name ($1, uuid));
  CHECK_ERROR (r == -1, \"$c_name\");

  rv = caml_copy_string (uuid);
  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+) : bool$/) {
	"\
  " . gen_unpack_args ($1) . "
  int r, b;

  NONBLOCKING (r = $c_name ($1, &b));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (b ? Val_true : Val_false);
"
    } elsif ($sig =~ /^(\w+), bool : unit$/) {
	"\
  " . gen_unpack_args ($1) . "
  int r, b;

  b = bv == Val_true ? 1 : 0;

  NONBLOCKING (r = $c_name ($1, b));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (Val_unit);
"
    } elsif ($sig eq "conn, int : int array") {
	"\
  CAMLlocal1 (rv);
  virConnectPtr conn = Connect_val (connv);
  int i = Int_val (iv);
  int *ids, r;

  /* Some libvirt List* functions still throw exceptions if i == 0,
   * so catch that and return an empty array directly.  This changes
   * the semantics slightly (masking other failures) but it's
   * unlikely anyone will care.  RWMJ 2008/06/10
   */
  if (i == 0) {
    rv = caml_alloc (0, 0);
    CAMLreturn (rv);
  }

  ids = malloc (sizeof (*ids) * i);
  if (ids == NULL)
    caml_raise_out_of_memory ();

  NONBLOCKING (r = $c_name (conn, ids, i));
  CHECK_ERROR_CLEANUP (r == -1, free (ids), \"$c_name\");

  rv = caml_alloc (r, 0);
  for (i = 0; i < r; ++i)
    Store_field (rv, i, Val_int (ids[i]));
  free (ids);

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), int : string array$/) {
	"\
  CAMLlocal2 (rv, strv);
  " . gen_unpack_args ($1) . "
  int i = Int_val (iv);
  char **names;
  int r;

  /* Some libvirt List* functions still throw exceptions if i == 0,
   * so catch that and return an empty array directly.  This changes
   * the semantics slightly (masking other failures) but it's
   * unlikely anyone will care.  RWMJ 2008/06/10
   */
  if (i == 0) {
    rv = caml_alloc (0, 0);
    CAMLreturn (rv);
  }

  names = malloc (sizeof (*names) * i);
  if (names == NULL)
    caml_raise_out_of_memory ();

  NONBLOCKING (r = $c_name ($1, names, i));
  CHECK_ERROR_CLEANUP (r == -1, free (names), \"$c_name\");

  rv = caml_alloc (r, 0);
  for (i = 0; i < r; ++i) {
    strv = caml_copy_string (names[i]);
    Store_field (rv, i, strv);
    free (names[i]);
  }
  free (names);

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), 0U? : string$/) {
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char *r;

  NONBLOCKING (r = $c_name ($1, 0));
  CHECK_ERROR (!r, \"$c_name\");

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), 0U? : unit$/) {
	"\
  " . gen_unpack_args ($1) . "
  int r;

  NONBLOCKING (r = $c_name ($1, 0));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (Val_unit);
"
    } elsif ($sig =~ /^(\w+) : unit$/) {
	"\
  " . gen_unpack_args ($1) . "
  int r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (Val_unit);
"
    } elsif ($sig =~ /^(\w+) : free$/) {
	"\
  " . gen_unpack_args ($1) . "
  int r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (r == -1, \"$c_name\");

  /* So that we don't double-free in the finalizer: */
  " . gen_free_arg ($1) . "

  CAMLreturn (Val_unit);
"
    } elsif ($sig =~ /^(\w+), string : unit$/) {
	"\
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  int r;

  NONBLOCKING (r = $c_name ($1, str));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (Val_unit);
"
    } elsif ($sig =~ /^(\w+), string, 0U? : unit$/) {
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  int r;

  NONBLOCKING (r = $c_name ($1, str, 0));
  CHECK_ERROR (!r, \"$c_name\");

  CAMLreturn (Val_unit);
"
    } elsif ($sig =~ /^(\w+), string : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, str));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), string, 0U? : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, str, 0));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), string, unsigned : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  unsigned int u = Int_val (uv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, str, u));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), (u?)int : unit$/) {
	my $unsigned = $2 eq "u" ? "unsigned " : "";
	"\
  " . gen_unpack_args ($1) . "
  ${unsigned}int i = Int_val (iv);
  int r;

  NONBLOCKING (r = $c_name ($1, i));
  CHECK_ERROR (r == -1, \"$c_name\");

  CAMLreturn (Val_unit);
"
    } elsif ($sig =~ /^(\w+), (u?)int : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($3);
	my $unsigned = $2 eq "u" ? "unsigned " : "";
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  ${unsigned}int i = Int_val (iv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, i));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($3) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), uuid : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  unsigned char *uuid = (unsigned char *) String_val (uuidv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, uuid));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), 0U? : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, 0));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+) : (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal1 (rv);
  " . gen_unpack_args ($1) . "
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (!r, \"$c_name\");

  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), string : (\w+) from (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal2 (rv, connv);
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, str));
  CHECK_ERROR (!r, \"$c_name\");

  connv = Field ($3v, 1);
  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), string, 0U? : (\w+) from (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal2 (rv, connv);
  " . gen_unpack_args ($1) . "
  char *str = String_val (strv);
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, str, 0));
  CHECK_ERROR (!r, \"$c_name\");

  connv = Field ($3v, 1);
  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+), 0U? : (\w+) from (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal2 (rv, connv);
  " . gen_unpack_args ($1) . "
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1, 0));
  CHECK_ERROR (!r, \"$c_name\");

  connv = Field ($3v, 1);
  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } elsif ($sig =~ /^(\w+) : (\w+) from (\w+)$/) {
	my $c_ret_type = short_name_to_c_type ($2);
	"\
  CAMLlocal2 (rv, connv);
  " . gen_unpack_args ($1) . "
  $c_ret_type r;

  NONBLOCKING (r = $c_name ($1));
  CHECK_ERROR (!r, \"$c_name\");

  connv = Field ($3v, 1);
  " . gen_pack_result ($2) . "

  CAMLreturn (rv);
"
    } else {
	die "unknown signature $sig"
    }
}

# Generate each function.

foreach my $function (@functions) {
    my $c_name = $function->{name};
    my $sig = $function->{sig};

    #print "generating $c_name with sig \"$sig\" ...\n";

    #my $is_pool_func = $c_name =~ /^virStoragePool/;
    #my $is_vol_func = $c_name =~ /^virStorageVol/;

    # Generate an equivalent C-external name for the function, unless
    # one is defined already.
    my $c_external_name;
    if (exists ($function->{c_external_name})) {
	$c_external_name = $function->{c_external_name};
    } elsif ($c_name =~ /^vir/) {
	$c_external_name = substr $c_name, 3;
	$c_external_name = camel_case_to_underscores ($c_external_name);
	$c_external_name = "ocaml_libvirt_" . $c_external_name;
    } else {
	die "cannot convert c_name $c_name to c_external_name"
    }

    print F <<END;
/* Automatically generated binding for $c_name.
 * In generator.pl this function has signature "$sig".
 */

END

    my @arg_names = gen_arg_names ($sig);
    my $nr_arg_names = scalar @arg_names;
    my $arg_names = join ", ", @arg_names;
    my $arg_names_as_values = join (", ", map { "value $_" } @arg_names);

    # Generate the start of the function, arguments.
    print F <<END;
CAMLprim value
$c_external_name ($arg_names_as_values)
{
  CAMLparam$nr_arg_names ($arg_names);
END

    # Generate the internals of the function.
    print F (gen_c_code ($sig, $c_name));

    # Finish off the function.
    print F <<END;
}

END
}

#----------------------------------------------------------------------

# Unimplemented functions.

if (@unimplemented) {
    printf "$0: warning: %d unimplemented functions\n", scalar (@unimplemented);

    print F <<'END';
/* The following functions are unimplemented and always fail.
 * See generator.pl '@unimplemented'
 */

END

    foreach my $c_external_name (@unimplemented) {
	print F <<END;
CAMLprim value
$c_external_name ()
{
  failwith ("$c_external_name is unimplemented");
}

END
    } # end foreach
} # end if @unimplemented

#----------------------------------------------------------------------

# Write the epilogue.

print F <<'END';
#include "libvirt_c_epilogue.c"

/* EOF */
END

close F;
print "$0: written $filename\n"

