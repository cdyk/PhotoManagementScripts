#!/usr/bin/perl -W

use strict;
use Time::Piece;
use Path::Class;
use Image::ExifTool qw/ :Public /;
use File::Copy;
use File::Find::Rule;

my $pretend = 1;
my $now = localtime;
my $path = shift || die "Missing import path";
my $photos_storage = dir( '/tmp/' );   # where photos are stored

# --- create template xmp with tag that identifies this import ---------------
my $import_tag = $now->strftime( 'import_%Y_%m_%d' );
my $exifTemplate = new Image::ExifTool;
$exifTemplate->SetNewValue( 'Subject' => $import_tag ) or die;
$exifTemplate->SetNewValue( 'HierarchicalSubject' => 'import|'.$import_tag ) or die;

# --- find all cr2-files in subdir -------------------------------------------
my @files = find( file =>
                  name => [qw/ *.cr2 *.CR2 /],
                  in   => $path );
unless( @files ) {
    say STDERR '[W]: No photos found.';
    exit;
}

# --- process all found files ------------------------------------------------

foreach my $file (sort @files) {
    say STDERR '[I] '.$file.': processing.';
    
    # try to extract exif image from the image
    my $exifTool = new Image::ExifTool;
    $exifTool->Options( DateFormat => '%Y:%m:%d' );
    unless( $exifTool->ExtractInfo($file) ) {
        say STDERR '[W] '.$file.': Failed to extract image info.';
    }

    # then, check if we can determine the date the photo was taken
    my $info = $exifTool->GetInfo( 'DateTimeOriginal' );
    unless( exists $$info{'DateTimeOriginal'} ) {
        # otherwise, we use current time
        say STDERR '[W] '.$file.': DateTimeOriginal missing, using current date.';
        $$info{ 'DateTimeOriginal' } = $now->strftime( '%Y:%m:%d' );
    }

    # extract year-month-day components and build path. I use a /YYYY/MM/DD
    # hierarchy to organize my photos.
    my ($year, $month, $day ) = split /:/, $$info{'DateTimeOriginal'};

    my $source = file($file);
    my $destination = $photos_storage->subdir($year)
                                     ->subdir($month)
                                     ->subdir($day)
                                     ->file( $source->basename );

    unless( $pretend ) {
        copy( $source, $destination ) or die "Copy failed: $!";
        $exifTemplate->WriteInfo( undef, $destination.'.xmp', 'XMP' ) or die $exifTool->GetValue('Error');
    }
    else {
        say STDERR '[I] Would copy '.$source.' to '.$destination;
        say STDERR '[I] Would create '.$destination.'.xmp';
    }
}

