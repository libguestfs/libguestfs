#!/usr/bin/env perl
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

=head1 NAME

make-internal-documentation.pl - Generate internal documentation from C files

=head1 SYNOPSIS

 make-internal-documentation.pl --output internal-documentation.pod
   [C source files ...]

=head1 DESCRIPTION

C<make-internal-documentation.pl> is a script that generates
L<guestfs-hacking(1)/INTERNAL DOCUMENTATION>.

You must specify the name of the output file using the I<-o> or
I<--output> option, and a list of the C source files in the project.

=head2 Function and struct documentation

Internal documentation is added to the C source files using special
comments which appear before function or struct definitions:

 /**
  * Returns true if C<foo> equals C<bar>.
  */
 bool
 is_equal (const char *foo, const char *bar)
 {
   ...

 /**
  * Struct used to store C<bar>s.
  */
 struct foo_bar {
   ...

The comment is written in POD format (see L<perlpod(1)>).  It may be
on several lines, and be split into paragraphs using blank lines.

The thing being documented should appear immediately after the special
comment, and is also copied into the documentation.

=head2 File documentation

In addition, each C file may have a special comment at the top of the
file (before any C<#include> lines) which outlines what the file does.

=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $man;

=item B<--man>

Display full documentation (man page).

=cut

my $output;

=item B<-o output.pod>

=item B<--output output.pod>

Set the name of the output file (required).

=cut

my $srcdir = ".";

=item B<--srcdir top_srcdir>

Path to the top source directory.  Input filenames are
located relative to this path.

=back

=cut

# Clean up the program name.
my $progname = $0;
$progname =~ s{.*/}{};

# Parse options.
GetOptions ("help|?" => \$help,
            "man" => \$man,
            "output=s" => \$output,
            "srcdir=s" => \$srcdir,
    ) or pod2usage (2);
pod2usage (-exitval => 0) if $help;
pod2usage (-exitval => 0, -verbose => 2) if $man;

die "$progname: missing -o/--output parameter\n" unless defined $output;

die "$progname: missing argument: make-internal-documentation [C source files ...]\n" unless @ARGV >= 1;

# Only consider input files which
#  - are C source or header files
#  - exist
#  - contain /** comments.

my @inputs = ();
my $input;
my $path;
foreach $input (@ARGV) {
    if ($input =~ /\.[ch]$/) {
        $path = "$srcdir/$input";
        if (-r $path) {
            my @cmd = ("grep", "-q", "^/\\*\\*", $path);
            if (system (@cmd) == 0) {
                push @inputs, $input
            }
        }
    }
}

# Sort the input files into directory sections.  Put the 'lib'
# directory first, and the rest follow in alphabetical order.
my %dirs = ();
foreach $input (@inputs) {
    die unless $input =~ m{^(.*)/([^/]+)$};
    $dirs{$1} = [] unless exists $dirs{$1};
    push @{$dirs{$1}}, $2
}
sub src_first {
    if ($a eq "lib" && $b eq "lib") { return 0 }
    elsif ($a eq "lib") { return -1 }
    elsif ($b eq "lib") { return 1 }
    else { return $a cmp $b }
}
my @dirs = sort src_first (keys %dirs);

open OUTPUT, ">$output" or die "$progname: $output: $!";

my $dir;
foreach $dir (@dirs) {
    print OUTPUT ("=head2 Subdirectory F<$dir>\n\n");

    my $file;
    foreach $file (sort @{$dirs{$dir}}) {
        my $input = "$dir/$file";
        $path = "$srcdir/$input";

        print OUTPUT ("=head3 File F<$input>\n\n");

        open INPUT, $path or die "$progname: $input: $!";

        # A single special comment seen before any #includes can be
        # used to outline the purpose of the source file.
        my $seen_includes = 0;
        my $lineno = 0;

        while (<INPUT>) {
            chomp;
            $lineno++;
            $seen_includes = 1 if /^#include/;

            if (m{^/\*\*$}) {
                # Found a special comment.  Read the whole comment.
                my @comment = ();
                my $found_end = 0;
                my $start_lineno = $lineno;
                while (<INPUT>) {
                    chomp;
                    $lineno++;

                    if (m{^ \*/$}) {
                        $found_end = 1;
                        last;
                    }
                    elsif (m{^ \* (.*)}) {
                        push @comment, $1;
                    }
                    elsif (m{^ \*$}) {
                        push @comment, "";
                    }
                    else {
                        die "$progname: $input: $lineno: special comment with incorrect format\n";
                    }
                }
                die "$progname: $input: $start_lineno: unterminated special comment"
                    unless $found_end;

                unless ($seen_includes) {
                    # If we've not seen the includes yet, then this is
                    # the top of file special comment, so we just
                    # write it out.
                    print OUTPUT join("\n", @comment), "\n";
                    print OUTPUT "\n";
                }
                else {
                    # Otherwise it's a function or struct description,
                    # so now we need to read in the definition.
                    my @defn = ();
                    my $thing = undef;
                    my $end = undef;
                    my $name = undef;
                    $found_end = 0;
                    $start_lineno = $lineno;
                    while (<INPUT>) {
                        chomp;
                        $lineno++;

                        if (defined $end) {
                            if ($_ eq $end) {
                                $found_end = 1;
                                last;
                            }
                            else {
                                push @defn, $_;
                            }
                        }
                        else {
                            # First line tells us if this is a struct,
                            # define or function.
                            if (/^struct ([\w_]+) \{$/) {
                                $thing = "Structure";
                                $name = $1;
                                $end = "};";
                            }
                            elsif (/^#define ([\w_]+)/) {
                                $thing = "Definition";
                                $name = $1;
                                $found_end = 1;
                                last;
                            }
                            else {
                                $thing = "Function";
                                $end = "{";
                            }
                            push @defn, $_;
                        }
                    }

                    die "$progname: $input: $start_lineno: unterminated $thing definition"
                        unless $found_end;

                    if ($thing eq "Function") {
                        # Try to determine the name of the function.
                        foreach (@defn) {
                            $name = $1 if /^([\w_]+) \(/;
                        }
                        die "$progname: $input: $start_lineno: cannot find the name of this function"
                            unless defined $name;
                    }

                    if ($thing eq "Structure") {
                        push @defn, "};"
                    }

                    if ($thing eq "Definition") {
                        @defn = ( "#define $name" )
                    }

                    # Print the definition, followed by the comment.
                    print OUTPUT "=head4 $thing C<$input:$name>\n\n";
                    print OUTPUT " ", join ("\n ", @defn), "\n";
                    print OUTPUT "\n";
                    print OUTPUT join("\n", @comment), "\n";
                    print OUTPUT "\n";
                }
            }
            elsif (m{^/\*\*}) {
                die "$progname: $input: $lineno: special comment with incorrect format\n";
            }
        }

        close INPUT;
    }
}

close OUTPUT or die "$progname: $output: close: $!";

exit 0;

=head1 SEE ALSO

L<perlpod(1)>,
L<guestfs-hacking(1)>.

=head1 AUTHOR

Richard W.M. Jones.

=head1 COPYRIGHT

Copyright (C) 2012-2023 Red Hat Inc.
