#!/usr/bin/perl -W

use strict;
use Time::Piece;
use Path::Class;
use Image::ExifTool qw/ :Public /;
use File::Copy;
use File::Path qw/ make_path /;
use File::Find::Rule;

my $pretend = 0;
my $overwrite = 1;
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

my $i=0;
FILES: foreach my $file (sort @files) {
    say STDERR '[I] '.$file.': processing... ('.int($i/@files).'%)';
    
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
        my $commit = 1;

        # make sure that path exists
        make_path $destination->dir()->stringify;

        # check if photo file already exist, and optionally remove it
        if( -e $destination ) {
            if( $overwrite ) {
                unlink $destination;
            }
            else {
                $commit = 0;
            }
            say STDERR '[W] '.$destination.' already exist '.($overwrite?'removing':'skipping.');
        }

        # check if xmp file already exist, and optionally remove it
        if( -e $destination.'.xmp' ) {
            if( $overwrite ) {
                unlink $destination.'.xmp';
            }
            else {
                $commit = 0;
            }
            say STDERR '[W] '.$destination.'.xmp'.' already exist '.($overwrite?'removing':'skipping.');
        }

        # copy file and create xmp
        if($commit) {
            say STDERR '[I] copy '.$source.' to '.$destination;
            say STDERR '[I] create '.$destination.'.xmp';
            copy( $source, $destination ) or die "Copy failed: $!";
            $exifTemplate->WriteInfo( undef, $destination.'.xmp', 'XMP' ) or die $exifTool->GetValue('Error');
        }
    }
    else {
        say STDERR '[I] Would copy '.$source.' to '.$destination;
        say STDERR '[I] Would create '.$destination.'.xmp';
    }
    $i+=100;
}

