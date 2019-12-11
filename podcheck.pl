#!/usr/bin/env perl
# podcheck.pl
# Copyright (C) 2016 Red Hat Inc.
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

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;
use Pod::Man;

=head1 NAME

podcheck.pl - Compare man page and tools to check all arguments are documented

=head1 SYNOPSIS

 podcheck.pl virt-foo.pod ./virt-foo [--ignore=--arg,--arg,...]

=head1 DESCRIPTION

This script compares a manual page (eg. C<virt-foo.pod>) and the
corresponding tool (eg. C<./virt-foo>) and checks that each command
line argument is documented in the manual, and that there is no rogue
documentation for arguments which do not exist.  It works by running
the tool with the standard C<--long-options> and C<--short-options>
parameters and comparing their output with the man page.

You can also ignore options, in case this script gets things wrong or
if there are options that you don't intend to document.

=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $ignore = "";

=item B<--ignore=--arg,--arg,...>

Ignore the comma-separated list of arguments given.

=cut

my @inserts;

=item B<--insert filename:__PATTERN__>

This works like the L<podwrapper.pl(1)> I<--insert> option and should be
used where the POD includes patterns which podwrapper would substitute.

=cut

my @verbatims;

=item B<--verbatim filename:__PATTERN__>

This works like the podwrapper I<--verbatim> option and should be
used where the POD includes patterns which podwrapper would substitute.

=cut

my @paths;

=item B<--path DIR>

This works like the L<podwrapper.pl(1)> I<--path> option and should be
used where the POD includes patterns which podwrapper would substitute.

=cut

# Clean up the program name.
my $progname = $0;
$progname =~ s{.*/}{};

# Parse options.
GetOptions ("help|?" => \$help,
            "ignore=s" => \$ignore,
            "insert=s" => \@inserts,
            "path=s" => \@paths,
            "verbatim=s" => \@verbatims,
    ) or pod2usage (2);
pod2usage (1) if $help;

die "$progname: missing argument: podcheck.pl input.pod tool\n"
    unless @ARGV == 2;
my $input = $ARGV[0];
my $tool = $ARGV[1];

my %ignore = ();
$ignore{$_} = 1 foreach (split /,/, $ignore);

# Open the man page and slurp it in.
my $content = read_whole_file ($input);

# Perform @inserts.
foreach (@inserts) {
    my @a = split /:/, $_, 2;
    die "$progname: $input: no colon in parameter of --insert\n" unless @a >= 2;
    my $replacement = read_whole_file ($a[0]);
    my $oldcontent = $content;
    $content =~ s/$a[1]/$replacement/ge;
    die "$progname: $input: could not find pattern '$a[1]' in input file\n"
        if $content eq $oldcontent;
}

# Perform INCLUDE directives.
$content =~ s{__INCLUDE:([-a-z0-9_]+\.pod)__}
             {read_whole_file ("$1", use_path => 1)}ge;

# Perform @verbatims.
foreach (@verbatims) {
    my @a = split /:/, $_, 2;
    die "$progname: $input: no colon in parameter of --verbatim\n" unless @a >= 2;
    my $replacement = read_verbatim_file ($a[0]);
    my $oldcontent = $content;
    $content =~ s/$a[1]/$replacement/ge;
    die "$progname: $input: could not find pattern '$a[1]' in input file\n"
        if $content eq $oldcontent;
}

# Perform VERBATIM directives.
$content =~ s{__VERBATIM:([-a-z0-9_]+\.txt)__}
             {read_verbatim_file ("$1", use_path => 1)}ge;

# Run the tool with --long-options and --short-options.
my @tool_options = ();
open PIPE, "$tool --long-options |"
    or die "$progname: $tool --long-options: $!";
while (<PIPE>) {
    chomp;
    push @tool_options, $_;
}
close PIPE;
open PIPE, "$tool --short-options |"
    or die "$progname: $tool --short-options: $!";
while (<PIPE>) {
    chomp;
    push @tool_options, $_;
}
close PIPE;

my %tool_option_exists = ();
$tool_option_exists{$_} = 1 foreach @tool_options;

# There are some tool options which we automatically ignore.
delete $tool_option_exists{"--color"};
delete $tool_option_exists{"--colour"};
delete $tool_option_exists{"--debug-gc"};

# Run the tool with --help.
my $help_content;
open PIPE, "LANG=C $tool --help |"
    or die "$progname: $tool --help: $!";
{
    local $/ = undef;
    $help_content = <PIPE>;
}
close PIPE;

# Do the tests.
my $errors = 0;

# Check each option exists in the manual.
my $tool_options_checked = 0;

foreach (sort keys %tool_option_exists) {
    unless ($ignore{$_}) {
        $tool_options_checked++;
        unless ($content =~ /^=item.*B<$_(?:=.*)?>/m) {
            $errors++;
            warn "$progname: $input does not define $_\n";
        }
    }
}

# Check there are no extra options defined in the manual which
# don't exist in the tool.
my $pod_options_checked = 0;

my %pod_options = ();
$pod_options{$_} = 1 foreach ( $content =~ /^=item.*B<(-[-\w]+)(?:=.*)?>/gm );
foreach (sort keys %pod_options) {
    unless ($ignore{$_}) {
        $pod_options_checked++;
        unless (exists $tool_option_exists{$_}) {
            $errors++;
            warn "$progname: $input defines option $_ which does not exist in the tool\n"
        }
    }
}

# Check the tool's --help output mentions all the options.  (For OCaml
# tools this is a waste of time since the --help output is generated,
# but for C tools it is a genuine test).
my $help_options_checked = 0;

my %help_options = ();
$help_options{$_} = 1 foreach ( $help_content =~ /(?<!\w)(-[-\w]+)/g );

# There are some help options which we automatically ignore.
delete $help_options{"--color"};
delete $help_options{"--colour"};
# "[--options]" is used as a placeholder for options in the synopsis
# text, so ignore it.
delete $help_options{"--options"};

foreach (sort keys %tool_option_exists) {
    unless ($ignore{$_}) {
        unless (exists $help_options{$_}) {
            $errors++;
            warn "$progname: $tool: option $_ does not appear in --help output\n"
        }
    }
}

foreach (sort keys %help_options) {
    unless ($ignore{$_}) {
        $help_options_checked++;
        unless (exists $tool_option_exists{$_}) {
            $errors++;
            warn "$progname: $tool: unknown option $_ appears in --help output\n"
        }
    }
}

exit 1 if $errors > 0;

printf "$progname: $tool: checked $tool_options_checked tool options, $pod_options_checked documented options, $help_options_checked help options\n";

exit 0;

sub find_file
{
    my $input = shift;
    my $use_path = shift;
    local $_;

    my @search_path = (".");
    push (@search_path, @paths) if $use_path;
    foreach (@search_path) {
        return "$_/$input" if -f "$_/$input";
    }
    die "$progname: $input: cannot find input file on path"
}

sub read_whole_file
{
    my $input = shift;
    my %options = @_;
    local $/ = undef;

    $input = find_file ($input, $options{use_path});
    open FILE, $input or die "$progname: $input: $!";
    $_ = <FILE>;
    close FILE;
    $_;
}

sub read_verbatim_file
{
    my $input = shift;
    my %options = @_;
    my $r = "";

    $input = find_file ($input, $options{use_path});
    open FILE, $input or die "$progname: $input: $!";
    while (<FILE>) {
        $r .= " $_";
    }
    close FILE;
    $r;
}

=head1 SEE ALSO

L<podwrapper.pl(1)>,
libguestfs.git/README.

=head1 AUTHOR

Richard W.M. Jones.

=head1 COPYRIGHT

Copyright (C) 2016 Red Hat Inc.
