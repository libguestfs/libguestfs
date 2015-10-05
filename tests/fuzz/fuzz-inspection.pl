#!/usr/bin/env perl
# Fuzz-test libguestfs inspection.
# Copyright (C) 2013 Red Hat Inc.
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

# The way this works is that we run inspection on an empty disk.  We
# register for a trace event callback so we can see inspection
# operations (like trying to look for directories or read files)
# before they happen.  We can then (randomly) decide to create these
# objects for inspection to find, and we see what happens.

use strict;
use warnings;

use Sys::Guestfs;
use Getopt::Long;

my $progname = $0;
$progname =~ s{.*/}{};

my $trace_depth = 0;

my $srcdir = $ENV{srcdir} || ".";
# Location of tests/data.
my $datasrcdir = $srcdir . "/../data";
my $databindir = "../data";
# Location of tests/guests/guest-aux.
my $guestauxsrcdir = $srcdir . "/../guests/guest-aux";
my $guestauxbindir = "../guests/guest-aux";

if ($ENV{SKIP_FUZZ_INSPECTION_PL}) {
    print "$progname: test skipped because environment variable set\n";
    exit 77
}

# So srand returns the seed.
if ($] < 5.014) {
    print "$progname: test skipped because perl < 5.14\n";
    exit 77
}

# Command line arguments.
# The defaults come from environment variables so we can set them
# from the Makefile.
my $help = 0;
my $iterations = exists $ENV{ITERATIONS} ? $ENV{ITERATIONS} : 10;
my $seed = 0;
GetOptions ("help|?" => \$help,
            "iterations|n=i" => \$iterations,
            "seed=i" => \$seed);
if ($help) {
    print "$progname [--seed=SEED] [--iterations=N|-n=N]\n";
    print "\n";
    print "  --iterations=N    Perform the test <N> times (default: 1)\n";
    print "  -n=N                  (if <N> = 0 then we loop forever)\n";
    print "\n";
    print "  --seed=SEED       Set the starting seed (to reproduce a test)\n";
    exit 0
}

if ($seed == 0) {
    # Choose a random seed.
    $seed = srand ();
}
else {
    # User specified --seed option.
    srand ($seed);
}

$| = 1;
print "$progname: random seed: $seed\n";

my $disksize = 1024 * 1024 * 1024;
my $g = Sys::Guestfs->new ();

# Note this is a fuzz test so the results are different each time it
# is run.  Therefore we enable tracing unconditionally so that the
# results can be reproduced.
$g->set_trace (1);

$g->add_drive_scratch ($disksize);
$g->launch ();

if ($iterations == 0) {
    run_one_test () while 1;
}
else {
    for (my $i = 0; $i < $iterations; ++$i) {
        print "Iteration: ", $i, "\n";
        run_one_test ();
    }
}

$g->shutdown ();
$g->close ();

sub run_one_test
{
    # Inspection doesn't especially depend on the way that the disk is
    # partitioned (just that filesystem(s) do exist).  So create a random
    # number of partitions >= 1.  We will populate them later.
    $g->part_init ("/dev/sda", "gpt");
    my $nr_parts = 1 + int (rand (6));
    my $startsect = 2048;
    my $partsize = int (($disksize / $nr_parts) / 512 / 2048 - 2) * 2048;
    my $i;
    for ($i = 0; $i < $nr_parts; ++$i) {
        $g->part_add ("/dev/sda", "p", $startsect, $startsect + $partsize - 1);
        $startsect += $partsize;
    }

    # Put random empty filesystems on each.  Again, inspection doesn't
    # care about the filesystem types (eg. Windows could be on ext2)
    # except that it differentiates between non-swap and swap.
    my @partitions = $g->list_partitions ();
    foreach (@partitions) {
        if (rand () < 0.75) {
            $g->mkfs ("ext2", $_);
        }
        else {
            $g->mkswap ($_);
        }
    }

    # Register a trace event handler so we can intervene randomly during
    # inspection.
    my $eh = $g->set_event_callback (\&trace_callback,
                                 $Sys::Guestfs::EVENT_TRACE);

    # Start inspection.
    # Note this is allowed to fail, it's not allowed to segfault.
    eval {
        my @roots = $g->inspect_os ();
        foreach (@roots) {
            print "root: ", $_, "\n";
            print "\ttype:    ", $g->inspect_get_type ($_), "\n";
            print "\tdistro:  ", $g->inspect_get_distro ($_), "\n";
            print "\tversion: ", $g->inspect_get_major_version ($_),
            ".", $g->inspect_get_minor_version ($_), "\n";
            print "\tproduct: ", $g->inspect_get_product_name ($_), "\n";
        }
    };
    if ($@) {
        warn "inspect_os: $@\n";
    }

    # Remove the trace event handler.
    $g->delete_event_callback ($eh);

    # Wipe the disk partitions.
    $g->wipefs ("/dev/sda");
    $g->zero ("/dev/sda");
}

# This is the trace event callback which sees inspection operations
# before they happen and can modify them by writing to the handle.
#
# XXX Note that parsing the trace log is super-hairy, but works fine
# for this purpose (monitoring inspection).  You wouldn't want to do
# this in real code, or rather, it would be better to explicitly add a
# way to capture arguments, eg. by adding a new "EVENT_ARG".
sub trace_callback {
    my ($event, $eh, $buf, $array) = @_;

    print "trace_callback[$trace_depth]: $buf\n";

    # Ignore return values.
    return if $buf =~ m/^\w+ = /;

    # Don't trace into calls that we are making.
    return if $trace_depth >= 1;
    $trace_depth++;

    eval {
        # is_dir
        if ($buf =~ m{^is_dir "(.*?)"}) {
            if (rand () < 0.4) {
                $g->remount ("/", rw => 1);
                $g->mkdir_p ($1);
            }
        }

        # is_file
        if ($buf =~ m{^is_file "(.*?)"}) {
            if (rand () < 0.4) {
                $g->remount ("/", rw => 1);
                random_file ($1);
            }
        }

        # exists (should be replaced with is_* where possible)
        if ($buf =~ m{^exists "(.*?)"}) {
            print "NOTICE: replace calls to exists (\"$1\") with is_file|dir\n";
            my $r = rand ();
            if ($r < 0.2) {
                $g->remount ("/", rw => 1);
                $g->mkdir_p ($1);
            }
            elsif ($r < 0.4) {
                $g->remount ("/", rw => 1);
                random_file ($1);
            }
            # else no replacement
        }

        # case_sensitive_path is used like exists for Windows inspection code
        if ($buf =~ m{^case_sensitive_path "(.*)?"}) {
            my $r = rand ();
            if ($r < 0.2) {
                $g->remount ("/", rw => 1);
                $g->mkdir_p ($1);
            }
            elsif ($r < 0.4) {
                $g->remount ("/", rw => 1);
                random_file ($1);
            }
            # else no replacement
        }

        # more here ...
    };
    if ($@) {
        warn "trace_callback: $@ [ignored]\n";
    }
    $trace_depth--;
}

# This creates a random file.  The content depends on the pathname.
sub random_file
{
    my $filename = shift;

    # If the file/directory exists already, assume we've created it in
    # a previous test and don't create it again.
    return if $g->exists ($filename);

    # Create the path leading up to the file, if it doesn't exist.
    my $path = $filename;
    $path =~ s{[^/]+$}{};
    $g->mkdir_p ($path);

    # Randomly replace any file with a huge file.
    if (rand () < 0.1) {
        $g->touch ($filename);
        $g->truncate_size ($filename, int (rand(1000)) * 1024 * 1024);
        return;
    }

    # Useful command:
    #   grep -oEh '"/etc[^"]*"' src/inspect*.c | sort -u

    if ($filename eq "/etc/fstab") {
        random_file_fstab ($filename);
    } elsif ($filename eq "/etc/lsb-release") {
        random_file_lsb_release ($filename);
    } elsif ($filename eq "/etc/redhat-release") {
        random_file_redhat_release ($filename);
    } elsif ($filename eq "/etc/SuSE-release") {
        random_file_suse_release ($filename);
    } elsif ($filename eq "/etc/mdadm.conf") {
        random_file_mdadm_conf ($filename);
    } elsif ($filename eq "/etc/rc.conf") {
        random_file_freebsd_rc_conf ($filename);
    } elsif ($filename eq "/etc/hostname" || $filename eq "/etc/HOSTNAME") {
        random_file_expects_one_line ($filename);
    } elsif ($filename eq "/etc/sysconfig/network") {
        random_file_sysconfig_network ($filename);
    } elsif ($filename eq "/grub/grub.conf" ||
             $filename eq "/grub/menu.lst") {
        random_file_grub_conf ($filename);
    } elsif ($filename eq "/grub2/grub.cfg") {
        random_file_grub2_conf ($filename);
    } elsif ($filename =~ m{^/etc/.*release} ||
             $filename eq "/etc/debian_version" ||
             $filename eq "/etc/freebsd-update.conf" ||
             $filename eq "/etc/ttylinux-target") {
        random_file_release ($filename);
    } elsif ($filename =~ m{^/bin/} ||
             $filename =~ m{\.exe$}) {
        random_file_binary ($filename);
    } elsif ($filename =~ m{/system32/config/}) {
        random_file_hive ($filename);
    } elsif ($filename =~ m{/txtsetup\.sif$} ||
             $filename eq "/.treeinfo" ||
             $filename eq "/.discinfo" ||
             $filename =~ m{^/\.disk} ||
             $filename =~ m{\.bat$} ||
             $filename =~ m{^/FDOS}) {
        random_file_expects_small_config ($filename);
    } else {
        print "NOTICE: no specific file replacement function for \"$filename\"\n";
        random_file_release ($filename);
    }
}

sub random_file_fstab
{
    my $filename = shift;

    my @lines = ();

    for (1 .. int (rand (10))) {
        my $spec = random_choice ("-", nonsense_string (),
                                  "/dev/floppy",
                                  "UUID=" . nonsense_string (),
                                  "LABEL=" . nonsense_string (),
                                  "/dev/root", "/dev/sda1", "/dev/sda2",
                                  "/dev/sdb1");
        my $file = random_choice ("/", "/" . nonsense_string ());
        my $vfstype = random_choice ("btrfs", "nfs", "ext2", "vfat");
        my $mntops = random_choice ("-", "subvol=" . nonsense_string ());
        my $freq = random_choice ("-", "0", "1", "2");
        my $passno = random_choice ("-", "0", "1", "2");

        push @lines, join (" ", $spec, $file, $vfstype, $mntops, $freq, $passno)
    }
    my $content = join "\n", @lines;
    $g->write ($filename, $content);
}

sub random_file_lsb_release
{
    my $filename = shift;

    my @lines = ();

    for (1 .. int (rand (10))) {
        my $key = random_choice ("", nonsense_string (),
                                 "LSB_VERSION", "DISTRIB_ID", "DISTRIB_RELEASE",
                                 "DISTRIB_CODENAME", "DISTRIB_DESCRIPTION");
        my $value = random_choice ("", nonsense_string (),
                                   "lsb-4.0-amd64", "FooBar", "1.0",
                                   "\"Foo Bar\"", "\"1.0\"");
        push @lines, "$key=$value";
    }

    my $content = join "\n", @lines;
    $g->write ($filename, $content);
}

sub random_file_redhat_release
{
    my $filename = shift;

    if (rand () < 0.5) {
        my $r = rand ();
        my $product = random_choice ("", nonsense_string (),
                                     "Fedora", "Red Hat",
                                     "Red Hat Desktop",
                                     "CentOS", "Scientific Linux");
        my $content;
        if ($r < 0.333) {
            $content = sprintf ("%s release 1", $product);
        } elsif ($r < 0.666) {
            $content = sprintf ("%s release 1 Update 2", $product);
        } else {
            $content = sprintf ("%s release 1.2", $product);
        }
        $g->write ($filename, $content);
    }
    else {
        random_file_release ($filename);
    }
}

sub random_file_suse_release
{
    my $filename = shift;

    if (rand () < 0.5) {
        my $r = rand ();
        my $product = random_choice ("", nonsense_string (),
                                     "openSUSE", "SeSE Linux", "SUSE LINUX",
                                     "SUSE Linux Enterprise",
                                     "Novell Linux Desktop");
        my $content;
        if ($r < 0.333) {
            $content = "%s 1.1";
        } elsif ($r < 0.66) {
            $content = "%s 1.1\nVERSION=1";
        } else {
            $content = "%s 1.1\nVERSION = 1\nPATCHLEVEL = 1";
        }
        $g->write ($filename, $content);
    }
    else {
        random_file_release ($filename);
    }
}

sub random_file_release
{
    my $filename = shift;

    my $r = rand ();
    if ($r < 0.3) {
        # An empty file.
        $g->write ($filename, "");
    } elsif ($r < 0.5) {
        # File with 1 line of nonsense.
        $g->write ($filename, nonsense_string ());
    } elsif ($r < 0.7) {
        # File with 1 line that could be a version number.
        $g->write ($filename, "foobar 1.0\n");
    } elsif ($r < 0.8) {
        # File with 1 line that could be a version number.
        $g->write ($filename, "foobar 1.0.3\n");
    } elsif ($r < 0.9) {
        # File with 2 lines.
        $g->write ($filename, "foobar 1.0.3\n" .
                   nonsense_string () . "\n");
    } else {
        # File with 3 lines.
        $g->write ($filename, "foobar 1.0.3\n" .
                   nonsense_string () . "\n" . nonsense_string ());
    }
}

sub random_file_expects_one_line
{
    my $filename = shift;
    my $r = rand ();

    if ($r < 0.333) {
        $g->write ($filename, "");
    } elsif ($r < 0.666) {
        $g->write ($filename, nonsense_string ());
    } else {
        $g->write ($filename, nonsense_string () . "\n" . nonsense_string ());
    }
}

sub random_file_mdadm_conf
{
    # XXX NOT IMPLEMENTED
    random_file_expects_small_config (@_)
}

sub random_file_grub_conf
{
    # XXX NOT IMPLEMENTED
    random_file_expects_small_config (@_)
}

sub random_file_grub2_conf
{
    # XXX NOT IMPLEMENTED
    random_file_expects_small_config (@_)
}

sub random_file_freebsd_rc_conf
{
    # XXX NOT IMPLEMENTED
    random_file_expects_small_config (@_)
}

sub random_file_sysconfig_network
{
    # XXX NOT IMPLEMENTED
    random_file_expects_small_config (@_)
}

sub random_file_expects_small_config
{
    my $filename = shift;

    my @lines = ();

    for (1 .. int (rand (10))) {
        my $r = rand ();

        if ($r < 0.5) {
            my $key = random_choice ("", nonsense_string (),
                                     "KEY");
            my $sep = random_choice (" = ", ": ");
            my $value = random_choice ("", nonsense_string (),
                                       "VALUE");
            push @lines, $key . $sep . $value;
        }
        elsif ($r < 0.75) {
            push @lines, "#" . nonsense_string ();
        }
        elsif ($r < 0.9) {
            push @lines, "";
        }
        else {
            push @lines, nonsense_string ();
        }
    }

    my $content = join "\n", @lines;
    $g->write ($filename, $content);
}

sub random_file_binary
{
    my $filename = shift;

    opendir (my $dh, $datasrcdir) or
        die "$progname: cannot open $datasrcdir: $!";
    my @binfiles = readdir ($dh);
    closedir ($dh);

    @binfiles = map { "$datasrcdir/$_" } @binfiles;
    @binfiles = grep { -f $_ && (m{/bin-} || m{/lib-}) } @binfiles;

    my $binfile = random_choice (@binfiles);
    $g->upload ($binfile, $filename);
}

sub random_file_hive
{
    my $filename = shift;

    my @hivefiles = ();
    $_ = $guestauxbindir . "/windows-software";
    push @hivefiles, $_ if -f $_;
    $_ = $guestauxbindir . "/windows-system";
    push @hivefiles, $_ if -f $_;

    if (@hivefiles > 0) {
        my $hivefile = random_choice (@hivefiles);
        $g->upload ($hivefile, $filename);
    } else {
        random_file_binary ($filename);
    }
}

sub random_choice { $_[rand @_] }

sub nonsense_string
{
    my @chars = ("a".."z", "0".."9", ".", "/");
    my $content = "";
    $content .= $chars[rand @chars] for 1..60;
    return $content;
}

exit 0
