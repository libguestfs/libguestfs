#!/usr/bin/perl -w

use strict;

use Sys::Guestfs;

# Look for LVM LVs, VGs and PVs in a guest image.

die "Usage: lvs.pl guest.img\n" if @ARGV != 1 || ! -f $ARGV[0];

print "Creating the libguestfs handle\n";
my $h = Sys::Guestfs->new ();
$h->add_drive ($ARGV[0]);

print "Launching, this can take a few seconds\n";
$h->launch ();
$h->wait_ready ();

print "Looking for PVs on the disk image\n";
my @pvs = $h->pvs ();
print "PVs found: (", join (", ", @pvs), ")\n";

print "Looking for VGs on the disk image\n";
my @vgs = $h->vgs ();
print "VGs found: (", join (", ", @vgs), ")\n";

print "Looking for LVs on the disk image\n";
my @lvs = $h->lvs ();
print "LVs found: (", join (", ", @lvs), ")\n";
