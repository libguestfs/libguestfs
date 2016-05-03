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

Internal documentation is added to the C source files using special
comments which look like this:

 /**
  * Returns true if C<foo> equals C<bar>.
  */
 bool
 is_equal (const char *foo, const char *bar)
   ...

The comment is written in POD format (see L<perlpod(1)>).  It may be
on several lines, and be split into paragraphs using blank lines.

The function being documented should appear immediately after the
special comment, and is also copied into the documentation.

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
#  - are C source files
#  - exist
#  - contain /** comments.

my @inputs = ();
my $input;
my $path;
foreach $input (@ARGV) {
    if ($input =~ /\.c$/) {
        $path = "$srcdir/$input";
        if (-r $path) {
            my @cmd = ("grep", "-q", "^/\\*\\*", $path);
            if (system (@cmd) == 0) {
                push @inputs, $input
            }
        }
    }
}
@inputs = sort @inputs;

open OUTPUT, ">$output" or die "$progname: $output: $!";

foreach $input (@inputs) {
    $path = "$srcdir/$input";

    print OUTPUT ("=head2 F<$input>\n\n");

    open INPUT, $path or die "$progname: $input: $!";

    # A single special comment seen before any #includes can be used
    # to outline the purpose of the source file.
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
                # If we've not seen the includes yet, then this is the
                # top of file special comment, so we just write it out.
                print OUTPUT join("\n", @comment), "\n";
                print OUTPUT "\n";
            }
            else {
                # Otherwise it's a function description, so now we
                # need to read in the function definition.
                my @function = ();
                $found_end = 0;
                $start_lineno = $lineno;
                while (<INPUT>) {
                    chomp;
                    $lineno++;

                    if (m/^{/) {
                        $found_end = 1;
                        last;
                    }
                    else {
                        push @function, $_;
                    }
                }

                die "$progname: $input: $start_lineno: unterminated function definition"
                    unless $found_end;

                # Print the function definition, followed by the comment.
                print OUTPUT " ", join ("\n ", @function), "\n";
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

close OUTPUT or die "$progname: $output: close: $!";

exit 0;

=head1 SEE ALSO

L<perlpod(1)>,
L<guestfs-hacking(1)>.

=head1 AUTHOR

Richard W.M. Jones.

=head1 COPYRIGHT

Copyright (C) 2012-2016 Red Hat Inc.
