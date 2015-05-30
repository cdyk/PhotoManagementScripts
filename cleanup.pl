#!/usr/bin/perl -W

use strict;
use File::Find::Rule;

my $dryrun             = 1;

my @keep_suffices = ('.cr2', '.CR2');
my @kill_suffices = ('.jpg', '.jpeg', '.JPG', '.JPEG');

sub print_help {
        print STDERR "Recognized options:\n";
        print STDERR "    --help               This help\n";
        print STDERR "    --dryrun             Don't actually write anything.\n";
        print STDERR "    --no-dryrun          Actually do stuff.\n";
}

my $path;

while( my $arg = shift @ARGV ) {
    if( $arg eq "--help" ) {
        print_help();
        exit(0);
    }
    elsif( $arg eq "--dryrun" ) {
        $dryrun = 1;
    }
    elsif( $arg eq "--no-dryrun" ) {
        $dryrun = 0;
    }
    else {
        $path = $arg;
        last;
    }
}

die "No path given" unless $path;

my @files = find( file => 
                  name => [map { '*'.$_} @keep_suffices],
                  in   => $path );

my %kill;

foreach my $file (@files) {
    my $stem = $file;
    $stem =~ s/\.\w+$//;

    foreach my $kill_suffix (@kill_suffices) {
        my $candidate = $stem.$kill_suffix;
        if( -e $candidate ) {
            $kill{$candidate} = $file;
        }
    }
}

foreach my $candidate (sort keys %kill) {
    my $original = $kill{$candidate};

    print "Removing $candidate, clone of $original\n";

    unless($dryrun) {
        unlink $candidate;
    }
}

