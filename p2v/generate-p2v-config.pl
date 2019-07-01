#!/usr/bin/env perl
# Copyright (C) 2019 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;

use Class::Struct;
use Getopt::Long;
use List::Util qw(any);

struct ConfigSection =>
{
  name => '$',
  elements => '@',
};

struct ConfigString =>
{
  name => '$',
};

struct ConfigInt =>
{
  name => '$',
  value => '$',
};

struct ConfigBool =>
{
  name => '$',
};

struct ConfigUInt64 =>
{
  name => '$',
};

struct ConfigUnsigned =>
{
  name => '$',
};

struct ConfigEnum =>
{
  name => '$',
  enum => '$',
};

struct ConfigStringList =>
{
  name => '$',
};

struct manual_entry =>
{
  shortopt => '$',
  description => '$',
};

# Enums.
my @enums = (
  ["basis", (
    ["BASIS_UNKNOWN",   "unknown",   "RTC could not be read"],
    ["BASIS_UTC",       "utc",       "RTC is either UTC or an offset from UTC"],
    ["BASIS_LOCALTIME", "localtime", "RTC is localtime"],
  )],
  ["output_allocation", (
    ["OUTPUT_ALLOCATION_NONE",         "none", "output allocation not set"],
    ["OUTPUT_ALLOCATION_SPARSE",       "sparse",       "sparse"],
    ["OUTPUT_ALLOCATION_PREALLOCATED", "preallocated", "preallocated"],
  )],
);

# Configuration fields.
my @fields = [
  ConfigSection->new(
    name => 'remote',
    elements => [
      ConfigString->new(name => 'server'),
      ConfigInt->new(name => 'port', value => 22),
    ],
  ),
  ConfigSection->new(
    name => 'auth',
    elements => [
      ConfigString->new(name => 'username'),
      ConfigString->new(name => 'password'),
      ConfigSection->new(
        name => 'identity',
        elements => [
          ConfigString->new(name => 'url'),
          ConfigString->new(name => 'file'),
          ConfigBool->new(name => 'file_needs_update'),
        ],
      ),
      ConfigBool->new(name => 'sudo'),
    ],
  ),
  ConfigString->new(name => 'guestname'),
  ConfigInt->new(name => 'vcpus', value => 0),
  ConfigUInt64->new(name => 'memory'),
  ConfigSection->new(
    name => 'cpu',
    elements => [
      ConfigString->new(name => 'vendor'),
      ConfigString->new(name => 'model'),
      ConfigUnsigned->new(name => 'sockets'),
      ConfigUnsigned->new(name => 'cores'),
      ConfigUnsigned->new(name => 'threads'),
      ConfigBool->new(name => 'acpi'),
      ConfigBool->new(name => 'apic'),
      ConfigBool->new(name => 'pae'),
    ],
  ),
  ConfigSection->new(
    name => 'rtc',
    elements => [
      ConfigEnum->new(name => 'basis', enum => 'basis'),
      ConfigInt->new(name => 'offset', value => 0),
    ],
  ),
  ConfigStringList->new(name => 'disks'),
  ConfigStringList->new(name => 'removable'),
  ConfigStringList->new(name => 'interfaces'),
  ConfigStringList->new(name => 'network_map'),
  ConfigSection->new(
    name => 'output',
    elements => [
      ConfigString->new(name => 'type'),
      ConfigEnum->new(name => 'allocation', enum => 'output_allocation'),
      ConfigString->new(name => 'connection'),
      ConfigString->new(name => 'format'),
      ConfigString->new(name => 'storage'),
    ],
  ),
];

# Some /proc/cmdline p2v.* options were renamed when we introduced
# the generator.  This map creates backwards compatibility mappings
# for these.
my @cmdline_aliases = (
  ["p2v.remote.server",     "p2v.server"],
  ["p2v.remote.port",       "p2v.port"],
  ["p2v.auth.username",     "p2v.username"],
  ["p2v.auth.password",     "p2v.password"],
  ["p2v.auth.identity.url", "p2v.identity"],
  ["p2v.auth.sudo",         "p2v.sudo"],
  ["p2v.guestname",         "p2v.name"],
  ["p2v.network_map",       "p2v.network"],
  ["p2v.output.type",       "p2v.o"],
  ["p2v.output.allocation", "p2v.oa"],
  ["p2v.output.connection", "p2v.oc"],
  ["p2v.output.format",     "p2v.of"],
  ["p2v.output.storage",    "p2v.os"],
);

# Some config entries are not exposed on the kernel command line.
my @cmdline_ignore = (
  "p2v.auth.identity.file",
  "p2v.auth.identity.file_needs_update",
);

# Man page snippets for each kernel command line setting.
my %cmdline_manual = (
  "p2v.remote.server" => manual_entry->new(
    shortopt => "SERVER",
    description => "
The name or IP address of the conversion server.

This is always required if you are using the kernel configuration
method.  If virt-p2v does not find this on the kernel command line
then it switches to the GUI (interactive) configuration method.",
  ),
  "p2v.remote.port" => manual_entry->new(
    shortopt => "PORT",
    description => "
The SSH port number on the conversion server (default: C<22>).",
  ),
  "p2v.auth.username" => manual_entry->new(
    shortopt => "USERNAME",
    description => "
The SSH username that we log in as on the conversion server
(default: C<root>).",
  ),
  "p2v.auth.password" => manual_entry->new(
    shortopt => "PASSWORD",
    description => "
The SSH password that we use to log in to the conversion server.

The default is to try with no password.  If this fails then virt-p2v
will ask the user to type the password (probably several times during
conversion).

This setting is ignored if C<p2v.auth.identity.url> is present.",
  ),
  "p2v.auth.identity.url" => manual_entry->new(
    shortopt => "URL",
    description => "
Provide a URL pointing to an SSH identity (private key) file.  The URL
is interpreted by L<curl(1)> so any URL that curl supports can be used
here, including C<https://> and C<file://>.  For more information on
using SSH identities, see L</SSH IDENTITIES> below.

If C<p2v.auth.identity.url> is present, it overrides C<p2v.auth.password>.
There is no fallback.",
  ),
  "p2v.auth.sudo" => manual_entry->new(
    shortopt => "", # ignored for booleans
    description => "
Use C<p2v.sudo> to tell virt-p2v to use L<sudo(8)> to gain root
privileges on the conversion server after logging in as a non-root
user (default: do not use sudo).",
  ),
  "p2v.guestname" => manual_entry->new(
    shortopt => "GUESTNAME",
    description => "
The name of the guest that is created.  The default is to try to
derive a name from the physical machine’s hostname (if possible) else
use a randomly generated name.",
  ),
  "p2v.vcpus" => manual_entry->new(
    shortopt => "N",
    description => "
The number of virtual CPUs to give to the guest.  The default is to
use the same as the number of physical CPUs.",
  ),
  "p2v.memory" => manual_entry->new(
    shortopt => "n(M|G)",
    description => "
The size of the guest memory.  You must specify the unit such as
megabytes or gigabytes by using for example C<p2v.memory=1024M> or
C<p2v.memory=1G>.

The default is to use the same amount of RAM as on the physical
machine.",
  ),
  "p2v.cpu.vendor" => manual_entry->new(
    shortopt => "VENDOR",
    description => "
The vCPU vendor, eg. \"Intel\" or \"AMD\".  The default is to use
the same CPU vendor as the physical machine.",
  ),
  "p2v.cpu.model" => manual_entry->new(
    shortopt => "MODEL",
    description => "
The vCPU model, eg. \"IvyBridge\".  The default is to use the same
CPU model as the physical machine.",
  ),
  "p2v.cpu.sockets" => manual_entry->new(
    shortopt => "N",
    description => "
Number of vCPU sockets to use.  The default is to use the same as the
physical machine.",
  ),
  "p2v.cpu.cores" => manual_entry->new(
    shortopt => "N",
    description => "
Number of vCPU cores to use.  The default is to use the same as the
physical machine.",
  ),
  "p2v.cpu.threads" => manual_entry->new(
    shortopt => "N",
    description => "
Number of vCPU hyperthreads to use.  The default is to use the same
as the physical machine.",
  ),
  "p2v.cpu.acpi" => manual_entry->new(
    shortopt => "", # ignored for booleans
    description => "
Whether to enable ACPI in the remote virtual machine.  The default is
to use the same as the physical machine.",
  ),
  "p2v.cpu.apic" => manual_entry->new(
    shortopt => "", # ignored for booleans
    description => "
Whether to enable APIC in the remote virtual machine.  The default is
to use the same as the physical machine.",
  ),
  "p2v.cpu.pae" => manual_entry->new(
    shortopt => "", # ignored for booleans
    description => "
Whether to enable PAE in the remote virtual machine.  The default is
to use the same as the physical machine.",
  ),
  "p2v.rtc.basis" => manual_entry->new(
    shortopt => "", # ignored for enums
    description => "
Set the basis of the Real Time Clock in the virtual machine.  The
default is to try to detect this setting from the physical machine.",
  ),
  "p2v.rtc.offset" => manual_entry->new(
    shortopt => "[+|-]HOURS",
    description => "
The offset of the Real Time Clock from UTC.  The default is to try
to detect this setting from the physical machine.",
  ),
  "p2v.disks" => manual_entry->new(
    shortopt => "sda,sdb,...",
    description => "
A list of physical hard disks to convert, for example:

 p2v.disks=sda,sdc

The default is to convert all local hard disks that are found.",
  ),
  "p2v.removable" => manual_entry->new(
    shortopt => "sra,srb,...",
    description => "
A list of removable media to convert.  The default is to create
virtual removable devices for every physical removable device found.
Note that the content of removable media is never copied over.",
  ),
  "p2v.interfaces" => manual_entry->new(
    shortopt => "em1,...",
    description => "
A list of network interfaces to convert.  The default is to create
virtual network interfaces for every physical network interface found.",
  ),
  "p2v.network_map" => manual_entry->new(
    shortopt => "interface:target,...",
    description => "
Controls how network interfaces are connected to virtual networks on
the target hypervisor.  The default is to connect all network
interfaces to the target C<default> network.

You give a comma-separated list of C<interface:target> pairs, plus
optionally a default target.  For example:

 p2v.network=em1:ovirtmgmt

maps interface C<em1> to target network C<ovirtmgmt>.

 p2v.network=em1:ovirtmgmt,em2:management,other

maps interface C<em1> to C<ovirtmgmt>, and C<em2> to C<management>,
and any other interface that is found to C<other>.",
  ),
  "p2v.output.type" => manual_entry->new(
    shortopt => "(libvirt|local|...)",
    description => "
Set the output mode.  This is the same as the virt-v2v I<-o> option.
See L<virt-v2v(1)/OPTIONS>.

If not specified, the default is C<local>, and the converted guest is
written to F</var/tmp>.",
  ),
  "p2v.output.allocation" => manual_entry->new(
    shortopt => "", # ignored for enums
    description => "
Set the output allocation mode.  This is the same as the virt-v2v
I<-oa> option.  See L<virt-v2v(1)/OPTIONS>.",
  ),
  "p2v.output.connection" => manual_entry->new(
    shortopt => "URI",
    description => "
Set the output connection libvirt URI.  This is the same as the
virt-v2v I<-oc> option.  See L<virt-v2v(1)/OPTIONS> and
L<http://libvirt.org/uri.html>",
  ),
  "p2v.output.format" => manual_entry->new(
    shortopt => "(raw|qcow2|...)",
    description => "
Set the output format.  This is the same as the virt-v2v I<-of>
option.  See L<virt-v2v(1)/OPTIONS>.",
  ),
  "p2v.output.storage" => manual_entry->new(
    shortopt => "STORAGE",
    description => "
Set the output storage.  This is the same as the virt-v2v I<-os>
option.  See L<virt-v2v(1)/OPTIONS>.

If not specified, the default is F</var/tmp> (on the conversion server).",
  ),
);

# Clean up the program name.
my $progname = $0;
$progname =~ s{.*/}{};

my $filename;
my $output;

GetOptions(
  'file=s' => \$filename,
  'output=s' => \$output,
  'help' => sub { pod2usage(1); },
) or pod2usage(2);
die "$progname: Option --file not specified.\n" unless $filename;
# die "$progname: Option --output not specified.\n" unless $output;

sub print_generated_header {
  my $fh = shift;
  print $fh <<"EOF";
/* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED FROM THE FOLLOWING FILES:
 *          $filename
 * ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
 */

EOF
}

sub generate_config_struct {
  my ($fh, $name, $fields) = @_;
  # If there are any ConfigSection (sub-structs) in any of the
  # fields then output those first.
  foreach my $field (@$fields) {
    if (ref($field) eq 'ConfigSection') {
      generate_config_struct($fh, $field->name . "_config", $field->elements);
    }
  }

  # Now generate this struct.
  print $fh "struct $name {\n";
  foreach my $field (@$fields) {
    my $type = ref($field);
    if ($type eq 'ConfigSection') {
      printf $fh "  struct %s_config %s;\n", $field->name, $field->name;
    } elsif ($type eq 'ConfigString') {
      printf $fh "  char *%s;\n", $field->name;
    } elsif ($type eq 'ConfigInt') {
      printf $fh "  int %s;\n", $field->name;
    } elsif ($type eq 'ConfigBool') {
      printf $fh "  bool %s;\n", $field->name;
    } elsif ($type eq 'ConfigUInt64') {
      printf $fh "  uint64_t %s;\n", $field->name;
    } elsif ($type eq 'ConfigUnsigned') {
      printf $fh "  unsigned %s;\n", $field->name;
    } elsif ($type eq 'ConfigEnum') {
      printf $fh "  enum %s %s;\n", $field->enum, $field->name;
    } elsif ($type eq 'ConfigStringList') {
      printf $fh "  char **%s;\n", $field->name;
    }
  }
  print $fh "};\n";
  print $fh "\n"
}

sub generate_p2v_config_h {
  my $fh = shift;
  print_generated_header($fh);
  print $fh <<"EOF";
#ifndef GUESTFS_P2V_CONFIG_H
#define GUESTFS_P2V_CONFIG_H

#include <stdbool.h>
#include <stdint.h>

EOF

  # Generate enums.
  foreach my $enum (@enums) {
    my $name = shift @$enum;
    print $fh "enum $name {\n";
    foreach my $items (@$enum) {
      my ($n, $foo, $comment) = @$items;
      printf $fh "  %-25s /* %s */\n", ($n . ","), $comment;
    }
    print $fh "};\n";
    print $fh "\n"
  }

  # Generate struct config.
  generate_config_struct($fh, "config", @fields);

  print $fh <<'EOF';
extern struct config *new_config (void);
extern struct config *copy_config (struct config *);
extern void free_config (struct config *);
extern void print_config (struct config *, FILE *);

#endif /* GUESTFS_P2V_CONFIG_H */
EOF
}

sub generate_field_initialization {
  my ($fh, $v, $fields) = @_;
  foreach my $field (@$fields) {
    my $type = ref($field);
    if ($type eq 'ConfigSection') {
      my $lv = $v . $field->name . '.';
      generate_field_initialization($fh, $lv, $field->elements);
    } elsif ($type eq 'ConfigInt') {
      if ($field->value > 0) {
        printf $fh "  %s%s = %d;\n", $v, $field->name, $field->value;
      }
    }
  }
}

sub generate_field_copy {
  my ($fh, $v, $fields) = @_;
  foreach my $field (@$fields) {
    my $type = ref($field);
    if ($type eq 'ConfigSection') {
      my $lv = $v . $field->name . '.';
      generate_field_copy($fh, $lv, $field->elements);
    } elsif ($type eq 'ConfigString') {
      printf $fh "  if (%s%s) {\n", $v, $field->name;
      printf $fh "    %s%s = strdup (%s%s);\n", $v, $field->name, $v, $field->name;
      printf $fh "    if (%s%s == NULL)\n", $v, $field->name;
      printf $fh "      error (EXIT_FAILURE, errno, \"strdup: %%s\", \"%s\");\n", $field->name;
      printf $fh "  }\n";
    } elsif ($type eq 'ConfigStringList') {
      printf $fh "  if (%s%s) {\n", $v, $field->name;
      printf $fh "    %s%s = guestfs_int_copy_string_list (%s%s);\n", $v, $field->name, $v, $field->name;
      printf $fh "    if (%s%s == NULL)\n", $v, $field->name;
      printf $fh "      error (EXIT_FAILURE, errno, \"copy string list: %%s\", \"%s\");\n", $field->name;
      printf $fh "  }\n";
    }
  }
}

sub generate_field_free {
  my ($fh, $v, $fields) = @_;
  foreach my $field (@$fields) {
    my $type = ref($field);
    if ($type eq 'ConfigSection') {
      my $lv = $v . $field->name . '.';
      generate_field_free($fh, $lv, $field->elements);
    } elsif ($type eq 'ConfigString') {
      printf $fh "  free (%s%s);\n", $v, $field->name;
    } elsif ($type eq 'ConfigStringList') {
      printf $fh "  guestfs_int_free_string_list (%s%s);\n", $v, $field->name;
    }
  }
}

sub generate_field_print {
  my ($fh, $prefix, $v, $fields) = @_;
  foreach my $field (@$fields) {
    my $type = ref($field);
    my $printable_name = defined($prefix)
                       ? $prefix . '.' . $field->name
                       : $field->name;
    if ($type eq 'ConfigSection') {
      my $lv = $v . $field->name . '.';
      generate_field_print($fh, $printable_name, $lv, $field->elements);
    } elsif ($type eq 'ConfigString') {
      print $fh "  fprintf (fp, \"%-20s %s\\n\",\n";
      printf $fh "           \"%s\", %s%s ? %s%s : \"(none)\");\n",
                 $printable_name, $v, $field->name, $v, $field->name;
    } elsif ($type eq 'ConfigInt') {
      print $fh "  fprintf (fp, \"%-20s %d\\n\",\n";
      printf $fh "           \"%s\", %s%s);\n", $printable_name, $v, $field->name;
    } elsif ($type eq 'ConfigBool') {
      print $fh "  fprintf (fp, \"%-20s %s\\n\",\n";
      printf $fh "           \"%s\", %s%s ? \"true\" : \"false\");\n",
                 $printable_name, $v, $field->name;
    } elsif ($type eq 'ConfigUInt64') {
      print $fh "  fprintf (fp, \"%-20s %\" PRIu64 \"\\n\",\n";
      printf $fh "           \"%s\", %s%s);\n", $printable_name, $v, $field->name;
    } elsif ($type eq 'ConfigUnsigned') {
      print $fh "  fprintf (fp, \"%-20s %u\\n\",\n";
      printf $fh "           \"%s\", %s%s);\n", $printable_name, $v, $field->name;
    } elsif ($type eq 'ConfigEnum') {
      printf $fh "  fprintf (fp, \"%%-20s \", \"%s\");\n", $printable_name;
      printf $fh "  print_%s (%s%s, fp);\n", $field->enum, $v, $field->name;
      print $fh "  fprintf (fp, \"\\n\");\n";
    } elsif ($type eq 'ConfigStringList') {
      printf $fh "  fprintf (fp, \"%%-20s\", \"%s\");\n", $printable_name;
      printf $fh "  if (%s%s) {\n", $v, $field->name;
      printf $fh "    for (i = 0; %s%s[i] != NULL; ++i)\n", $v, $field->name;
      printf $fh "      fprintf (fp, \" %%s\", %s%s[i]);\n", $v, $field->name;
      print $fh "  }\n";
      print $fh "  else\n";
      print $fh "    fprintf (fp, \" (none)\\n\");\n";
      print $fh "  fprintf (fp, \"\\n\");\n";
    }
  }
}

sub generate_p2v_config_c {
  my $fh = shift;
  print_generated_header($fh);
  print $fh <<"EOF";
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <errno.h>
#include <error.h>

#include "p2v.h"
#include "p2v-config.h"

/**
 * Allocate a new config struct.
 */
struct config *
new_config (void)
{
  struct config *c;

  c = calloc (1, sizeof *c);
  if (c == NULL)
    error (EXIT_FAILURE, errno, "calloc");

EOF

  generate_field_initialization($fh, "c->", @fields);

  print $fh <<"EOF";

  return c;
}

/**
 * Copy a config struct.
 */
struct config *
copy_config (struct config *old)
{
  struct config *c = new_config ();

  memcpy (c, old, sizeof *c);

  /* Need to deep copy strings and string lists. */
EOF

  generate_field_copy($fh, "c->", @fields);

  print $fh <<"EOF";

  return c;
}

/**
 * Free a config struct.
 */
void
free_config (struct config *c)
{
  if (c == NULL)
    return;

EOF

  generate_field_free($fh, "c->", @fields);

  print $fh <<"EOF";
}

EOF

  foreach my $enum (@enums) {
    my $name = shift @$enum;
    print $fh "static void\n";
    printf $fh "print_%s (enum %s v, FILE *fp)\n", $name, $name;
    print $fh "{\n";
    printf $fh "  switch (v) {\n";
    foreach my $items (@$enum) {
      my ($n, $cmdline, $foo) = @$items;
      printf $fh "  case %s:\n", $n;
      printf $fh "    fprintf (fp, \"%s\");\n", $cmdline;
      print $fh "    break;\n";
    }
    print $fh "  }\n";
    print $fh "}\n";
    print $fh "\n"
  }

  print $fh <<"EOF";
/**
 * Print the conversion parameters and other important information.
 */
void
print_config (struct config *c, FILE *fp)
{
  size_t i;

  fprintf (fp, \"%-20s %s\\n\", \"local version\", PACKAGE_VERSION_FULL);
  fprintf (fp, \"%-20s %s\\n\", \"remote version\",
           v2v_version ? v2v_version : \"unknown\");
EOF

  generate_field_print($fh, undef, "c->", @fields);

  print $fh <<"EOF";
}
EOF
}

sub find_alias {
  my $name = shift;
  foreach my $alias (@cmdline_aliases) {
    if ($name eq @$alias[0]) {
      return @$alias[1];
    }
  }
  return;
}

sub find_enum {
  my $name = shift;
  foreach my $enum (@enums) {
    my $n = shift @$enum;
    if ($n eq $name) {
      return @$enum;
    }
  }
  return;
}

sub generate_field_config {
  my ($fh, $prefix, $v, $fields) = @_;

  foreach my $field (@$fields) {
    my $type = ref($field);
    if ($type eq 'ConfigSection') {
      my $lprefix = $prefix . '.' . $field->name;
      my $lv = $v . $field->name . '.';
      generate_field_config($fh, $lprefix, $lv, $field->elements);
    } else {
      my $key = $prefix . '.' . $field->name;

      if (not (any { $_ eq $key } @cmdline_ignore)) {
        # Is there an alias for this field?
        my $alias = find_alias($key);

        printf $fh "  if ((p = get_cmdline_key (cmdline, \"%s\")) != NULL", $key;
        if (defined($alias)) {
          print $fh " ||\n";
          printf $fh "      (p = get_cmdline_key (cmdline, \"%s\")) != NULL", $alias;
        }
        print $fh ") {\n";

        # Parse the field.
        if ($type eq 'ConfigString') {
          printf $fh "    free (%s%s);\n", $v, $field->name;
          printf $fh "    %s%s = strdup (p);\n", $v, $field->name;
          printf $fh "    if (%s%s == NULL)\n", $v, $field->name;
          print $fh "      error (EXIT_FAILURE, errno, \"strdup\");\n";
        } elsif ($type eq 'ConfigInt') {
          printf $fh "    if (sscanf (p, \"%%d\", &%s%s) != 1)\n", $v, $field->name;
          print $fh "      error (EXIT_FAILURE, errno,\n";
          print $fh "             \"cannot parse %s=%s from the kernel command line\",\n";
          printf $fh "             \"%s\", p);\n", $key;
        } elsif ($type eq 'ConfigBool') {
          printf $fh "    %s%s = guestfs_int_is_true (p) || STREQ (p, \"\");\n", $v, $field->name;
        } elsif ($type eq 'ConfigUInt64') {
          print $fh "    xerr = xstrtoull (p, NULL, 0, &ull, \"0kKMGTPEZY\");\n";
          print $fh "    if (xerr != LONGINT_OK)\n";
          print $fh "      error (EXIT_FAILURE, 0,\n";
          print $fh "             \"cannot parse %s=%s from the kernel command line\",\n";
          printf $fh "             \"%s\", p);\n", $key;
          printf $fh "    %s%s = ull;\n", $v, $field->name;
        } elsif ($type eq 'ConfigUnsigned') {
          printf $fh "    if (sscanf (p, \"%%u\", &%s%s) != 1)\n", $v, $field->name;
          print $fh "      error (EXIT_FAILURE, errno,\n";
          print $fh "             \"cannot parse %s=%s from the kernel command line\",\n";
          printf $fh "             \"%s\", p);\n", $key;
        } elsif ($type eq 'ConfigEnum') {
          my @enum_choices = find_enum($field->enum) or die "cannot find ConfigEnum $field->enum";
          printf $fh "    ";
          foreach my $items (@enum_choices) {
            my ($n, $cmdline, $foo) = @$items;
            printf $fh "if (STREQ (p, \"%s\"))\n", $cmdline;
            printf $fh "      %s%s = %s;\n", $v, $field->name, $n;
            print $fh "    else ";
          }
          print $fh "{\n";
          print $fh "      error (EXIT_FAILURE, 0,\n";
          print $fh "             \"invalid value %s=%s from the kernel command line\",\n";
          printf $fh "             \"%s\", p);\n", $key;
          print $fh "    }\n";
        } elsif ($type eq 'ConfigStringList') {
          printf $fh "    guestfs_int_free_string_list (%s%s);\n", $v, $field->name;
          printf $fh "    %s%s = guestfs_int_split_string (',', p);\n", $v, $field->name;
          printf $fh "    if (%s%s == NULL)\n", $v, $field->name;
          print $fh "      error (EXIT_FAILURE, errno, \"strdup\");\n";
        }

        print $fh "  }\n";
        print $fh "\n";
      }
    }
  }
}

sub generate_p2v_kernel_config_c {
  my $fh = shift;
  print_generated_header($fh);
  print $fh <<"EOF";
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>

#include "xstrtol.h"

#include "p2v.h"
#include "p2v-config.h"

/**
 * Read the kernel command line and parse out any C<p2v.*> fields that
 * we understand into the config struct.
 */
void
update_config_from_kernel_cmdline (struct config *c, char **cmdline)
{
  const char *p;
  strtol_error xerr;
  unsigned long long ull;

EOF

  generate_field_config($fh, "p2v", "c->", @fields);

  print $fh <<"EOF";
  if (c->auth.identity.url != NULL)
    c->auth.identity.file_needs_update = 1;

  /* Undocumented command line parameter used for testing command line
   * parsing.
   */
  p = get_cmdline_key (cmdline, "p2v.dump_config_and_exit");
  if (p) {
    print_config (c, stdout);
    exit (EXIT_SUCCESS);
  }
}
EOF
}

sub generate_field_config_pod {
  my ($fh, $prefix, $fields) = @_;

  foreach my $field (@$fields) {
    my $type = ref($field);
    if ($type eq 'ConfigSection') {
      my $lprefix = $prefix . '.' . $field->name;
      generate_field_config_pod($fh, $lprefix, $field->elements);
    } else {
      my $key = $prefix . '.' . $field->name;

      if (not (any { $_ eq $key } @cmdline_ignore)) {
        # Is there an alias for this field?
        my $manual_entry = $cmdline_manual{$key} or die "missing manual entry for $key";

        # For booleans there is no shortopt field.  For enums
        # we generate it.
        my $shortopt;
        if ($type eq 'ConfigBool') {
          die "non-empty shortopt for $field->name" if $manual_entry->shortopt ne '';
          $shortopt = '';
        } elsif ($type eq 'ConfigEnum') {
          die "non-empty shortopt for $field->name" if $manual_entry->shortopt ne '';
          my @enum_choices = find_enum($field->enum) or die "cannot find ConfigEnum $field->enum";
          $shortopt = "=(" . join('|', map { $_->[1] } @enum_choices) . ")";
        } else {
          $shortopt = "=" . $manual_entry->shortopt;
        }

        # The description must not end with \n
        die "description of $key must not end with \\n" if $manual_entry->description =~ /\n\z/;

        # Is there an alias for this field?
        my $alias = find_alias($key);
        printf $fh "=item B<%s%s>\n\n", $key, $shortopt;
        if (defined($alias)) {
          printf $fh "=item B<%s%s>\n\n", $alias, $shortopt;
        }

        printf $fh "%s\n\n", $manual_entry->description;
      }
    }
  }
}

sub write_to {
  my $fn = shift;
  if (defined($output)) {
    open(my $fh, '>', $output) or die "Could not open file '$output': $!";
    $fn->($fh, @_);
    close($fh);
  } else {
    $fn->(*STDOUT, @_);
  }
}

if ($filename eq 'config.c') {
  write_to(\&generate_p2v_config_c);
} elsif ($filename eq 'kernel-config.c') {
  write_to(\&generate_p2v_kernel_config_c);
} elsif ($filename eq 'p2v-config.h') {
  write_to(\&generate_p2v_config_h);
} elsif ($filename eq 'virt-p2v-kernel-config.pod') {
  write_to(\&generate_field_config_pod, "p2v", @fields);
} else {
  die "$progname: unrecognized output file '$filename'\n";
}
