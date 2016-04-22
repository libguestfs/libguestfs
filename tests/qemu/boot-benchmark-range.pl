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

boot-benchmark-range.pl - Benchmark libguestfs across a range of commits
from another project

=head1 SYNOPSIS

 LIBGUESTFS_BACKEND=direct \
 LIBGUESTFS_HV=/path/to/qemu/x86_64-softmmu/qemu-system-x86_64 \
   ./run \
   tests/qemu/boot-benchmark-range.pl /path/to/qemu HEAD~50..HEAD

=head1

Run F<tests/qemu/boot-benchmark> across a range of commits in another
project.  This is useful for finding performance regressions in other
programs such as qemu or the Linux kernel which might be affecting
libguestfs.

For example, suppose you suspect there has been a performance
regression in qemu, somewhere between C<HEAD~50..HEAD>.  You could run
the script like this:

 LIBGUESTFS_BACKEND=direct \
 LIBGUESTFS_HV=/path/to/qemu/x86_64-softmmu/qemu-system-x86_64 \
   ./run \
   tests/qemu/boot-benchmark-range.pl /path/to/qemu HEAD~50..HEAD

where F</path/to/qemu> is the path to the qemu git repository.

The output is a list of the qemu commits, annotated by the benchmark
time and some other information about how the time compares to the
previous commit.

You should run these tests on an unloaded machine.  In particular
running a desktop environment, web browser and so on can make the
benchmarks useless.

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

my $benchmark_command;

=item B<--benchmark> C<boot-benchmark>

Set the name of the benchmark to run.  You only need to use this if
the script cannot find the right path to the libguestfs
F<tests/qemu/boot-benchmark> program.  By default the script looks for
this file in the same directory as its executable.

=cut

my $make_command = "make";

=item B<--make> C<make>

Set the command used to build the other project.  The default is
to run C<make>.

If the command fails, then the commit is skipped.

=back

=cut

# Clean up the program name.
my $progname = $0;
$progname =~ s{.*/}{};

# Parse options.
GetOptions ("help|?" => \$help,
            "man" => \$man,
            "benchmark=s" => \$benchmark_command,
            "make=s" => \$make_command,
    ) or pod2usage (2);
pod2usage (-exitval => 0) if $help;
pod2usage (-exitval => 0, -verbose => 2) if $man;

die "$progname: missing argument: requires path to git repository and range of commits\n" unless @ARGV == 2;

my $dir = $ARGV[0];
my $range = $ARGV[1];

die "$progname: $dir is not a git repository\n"
    unless -d $dir && -d "$dir/.git";

sub silently_run
{
    open my $saveout, ">&STDOUT";
    open my $saveerr, ">&STDERR";
    open STDOUT, ">/dev/null";
    open STDERR, ">/dev/null";
    my $ret = system (@_);
    open STDOUT, ">&", $saveout;
    open STDERR, ">&", $saveerr;
    return $ret;
}

# Find the benchmark program and check it works.
unless (defined $benchmark_command) {
    $benchmark_command = $0;
    $benchmark_command =~ s{/[^/]+$}{};
    $benchmark_command .= "/boot-benchmark";

    my $r = silently_run ("$benchmark_command", "--help");
    die "$progname: cannot locate boot-benchmark program, try using --benchmark\n" unless $r == 0;
}

# Get the top-most commit from the remote, and restore it on exit.
my $top_commit = `git -C '$dir' rev-parse HEAD`;
chomp $top_commit;

sub checkout
{
    my $sha = shift;
    my $ret = silently_run ("git", "-C", $dir, "checkout", $sha);
    return $ret;
}

END {
    checkout ($top_commit);
}

# Get the range of commits and log messages.
my @range = ();
open RANGE, "git -C '$dir' log --reverse --oneline $range |" or die;
while (<RANGE>) {
    if (m/^([0-9a-f]+) (.*)/) {
        my $sha = $1;
        my $msg = $2;
        push @range, [ $sha, $msg ];
    }
}
close RANGE or die;

# Run the test.
my $prev_ms;
foreach (@range) {
    my ($sha, $msg) = @$_;
    my $r;

    print "\n";
    print "$sha $msg\n";

    # Checkout this commit in the other repo.
    $r = checkout ($sha);
    if ($r != 0) {
        print "git checkout failed\n";
        next;
    }

    # Build the repo, silently.
    $r = silently_run ("cd $dir && $make_command");
    if ($r != 0) {
        print "build failed\n";
        next;
    }

    # Run the benchmark program and get the timing.
    my ($time_ms, $time_str);
    open BENCHMARK, "$benchmark_command | grep '^Result:' |" or die;
    while (<BENCHMARK>) {
        die unless m/^Result: (([\d.]+)ms ±[\d.]+ms)/;
        $time_ms = $2;
        $time_str = $1;
    }
    close BENCHMARK;

    print "\t", $time_str;
    if (defined $prev_ms) {
        if ($prev_ms > $time_ms) {
            my $pc = 100 * ($prev_ms-$time_ms) / $time_ms;
            if ($pc >= 1) {
                printf (" ↑ improves performance by %0.1f%%", $pc);
            }
        } elsif ($prev_ms < $time_ms) {
            my $pc = 100 * ($time_ms-$prev_ms) / $prev_ms;
            if ($pc >= 1) {
                printf (" ↓ degrades performance by %0.1f%%", $pc);
            }
        }
    }
    print "\n";
    $prev_ms = $time_ms;
}

=head1 SEE ALSO

L<git(1)>,
L<guestfs-performance(1)>.

=head1 AUTHOR

Richard W.M. Jones.

=head1 COPYRIGHT

Copyright (C) 2016 Red Hat Inc.
