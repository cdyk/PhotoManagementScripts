#!/usr/bin/perl -W

use strict;
use DBI;
use Image::ExifTool qw(:Public);
use URI::Escape;
use Encode qw(decode encode);
use Encode::Guess;

my $dryrun            = 1;
my $dump_xmp          = 0;
my $remove_jpg_if_cr2 = 1; 
my $photos_processed  = 0;
my $tag_encoding      = "Guess";
my $db_path           = "photos.db"; #"$ENV{'HOME'}/.config/f-spot/photos.db";

sub print_help {
        print STDERR "Recognized options:\n";
        print STDERR "    --help               This help\n";
        print STDERR "    --dryrun             Don't actually write anything.\n";
        print STDERR "    --no-dryrun          Actually do stuff.\n";
        print STDERR "    --db path            Specify path to F-Spot database.\n";
        print STDERR "    --remove_jpg_if_cr2  Remove jpg image if cr2 version exists.\n";
}

sub add_keywords
{
    my ($current, $to_add) = @_;

    my @tags = @{$current};

    if(ref($to_add) eq 'ARRAY') {
        push @tags, @{$to_add};
    }
    elsif(ref($to_add) eq 'SCALAR') {
        push @tags, split /, ?/, $to_add;
    }

    my %tag_hash = map { $_, 1 } @tags;

    [sort keys %tag_hash];
}

sub strip_suffix
{
    my $path = shift;
    $path =~ s/\.[^.\/\\]+$//;
    $path;
}


while( my $arg = shift @ARGV ) {
    if( $arg eq "--help" ) {
        print_help();
        exit(0);
    }
    elsif( $arg eq "--db" ) {
        unless( $db_path = shift @ARGV ) {
            print STDERR "--db expects an argument.\n";
            die;
        }
    }
    elsif( $arg eq "--dryrun" ) {
        $dryrun = 1;
    }
    elsif( $arg eq "--no-dryrun" ) {
        $dryrun = 0;
    }
    elsif( $arg eq "--remove_jpg_if_cr2" ) {
        $remove_jpg_if_cr2 = 1;
    }
    else {
        print STDERR "Unrecognized option '$arg'\n\n";
        print_help();
        die;
    }
}

# --- Connect to database ------------------------------------------------------
my $dbh = DBI->connect( "dbi:SQLite:$db_path" ) or die $DBI::errstr;

# --- Create tag hierarchies ---------------------------------------------------
my %tags;
{   
    my $sth = $dbh->prepare( "SELECT id, name, category_id FROM tags" ) or die $DBI::errstr;
    $sth->execute();
    while( my ($id, $name, $category_id) = $sth->fetchrow_array() ) {
        if( $tag_encoding ) {
            $name = decode( $tag_encoding, $name ) or die "Can't guess encoding of '$name'";
            $name = encode( "UTF-8", $name );
        }
        $tags{$id} = [[$name], $category_id ];
    }
    $sth->finish();

    # traverse hierarchy
    foreach my $id (keys %tags) {
        my $category = $tags{$id}[1];
        while( $category ) {
            unshift @{$tags{$id}[0]}, $tags{$category}[0][0];
            $category = $tags{$category}[1];
        }
    }
}

# --- Plow through photos ------------------------------------------------------
{   
    my $sth = $dbh->prepare( "SELECT id, base_uri, filename FROM photos" ) or die $DBI::errstr;
    $sth->execute();
    while( my ($id, $base_uri, $filename ) = $sth->fetchrow_array() ) {


        # ======================================================================
        # ===                                                                ===
        # === Determine all versions of this photo                           ===
        # ===                                                                ===
        # ======================================================================

        my $versions = $dbh->selectall_arrayref( "SELECT name, base_uri, filename ".
                                                 "FROM photo_versions ".
                                                 "WHERE photo_id='$id'".
                                                 "ORDER BY name DESC" )  or die $DBI::errstr;

        # --- If versions was empty, add the default from the photos table -----
        unless( @{$versions} ) {
            $versions = [ ['Default', $base_uri, $filename] ];
            print STDERR "[ID='$id'] No version info, reverting to default.\n";
        }

        # --- Clean up paths and discard non-existing files --------------------
        $versions = [grep {

            # Chop of file://-prefix and do url_decode to remove the %xx-stuff.
            $$_[3] = uri_unescape( substr( $$_[1], 7 )."/".$$_[2] );

            # Return true (keep) if file exist, otherwise false will remove it
            unless( -e $$_[3] ) {
                print STDERR "[ID='$id'] Skipping non-existing file '$$_[3]'\n";
                0;
            }
            else {
                1;
            }
        } @{$versions}];

        # --- If no valid file paths, skip to next entry ---------------------
        unless( @{$versions} ) {
            print STDERR "[ID='$id'] No valid file paths, skipping entry.\n";
            next;
        }

        # --- if we want to kill extracted jpg's when CR2 is present ---------
        if( ($remove_jpg_if_cr2)
            && (@{$versions} == 2)
            && ($$versions[0][0] eq 'Original') && (lc(substr($$versions[0][2],-4)) eq ".cr2")
            && ($$versions[1][0] eq 'Jpeg')     && ( (lc(substr($$versions[1][2],-4)) eq ".jpg")
                                                  || (lc(substr($$versions[1][2],-5)) eq ".jpeg") ) )
        {
            my @files = glob "$$versions[1][3]*";

            foreach my $item (@files) {
                print STDERR "[ID='$id'] Unlinking duplicate '$item'\n";
            }
            unless( $dryrun ) {
                unlink @files;
            }
            pop @{$versions};
        }

        # --- now, create tags for this photo --------------------------------
        my $photo_tags = $dbh->selectcol_arrayref( "SELECT tag_id ".
                                                   "FROM photo_tags ".
                                                   "WHERE photo_id='$id'" )  or die $DBI::errstr;

        next unless( @{$photo_tags} ); # No tags, no use in carrying on.

        my $dc_tags = [];
        my $lr_tags = [];
        foreach my $tag_id (@{$photo_tags}) {
            push @{$dc_tags}, @{$tags{$tag_id}[0]};
            push @{$lr_tags}, join('|',@{$tags{$tag_id}[0]});
        }

        # ======================================================================
        # ===                                                                ===
        # === Create or update XMP data                                      ===
        # ===                                                                ===
        # ======================================================================

        foreach my $version (@{$versions}) {

            # For cr2-files, we use a sidecar file, and for jpg files, we embed.
            
            my $embed = (lc(substr($$version[3],-4)) eq ".jpg")
                     || (lc(substr($$version[3],-5)) eq ".jpeg");

            next if $embed;


            # If we embed, merge with existing 
            if($embed) {
                my $exifTool = new Image::ExifTool;
                my $info = $exifTool->ImageInfo($$version[3]) or die $exifTool->GetValue('Error');
                if(exists $$info{'Subject'}) {
                    $dc_tags = add_keywords($dc_tags, $$info{'Subject'});
                }
                if(exists $$info{'HierarchicalSubject'}) {
                    $lr_tags = add_keywords($dc_tags, $$info{'HierarchicalSubject'});
                }
            }

            my $exifTool = new Image::ExifTool;

            # Dublin Core namespace tags
            $exifTool->SetNewValue( 'Subject' => $dc_tags ) or die $exifTool->GetValue('Error');

            # Adobe lightroom tags
            $exifTool->SetNewValue( 'HierarchicalSubject' => $lr_tags ) or die $exifTool->GetValue('Error');

            # --- check if we have an existing XMP file ------------------------
            my $xmpfilename = undef;
            if($embed) {
                $xmpfilename = $$version[3];
            }
            else {
                my $base = strip_suffix($$version[3]);
        
                if( -e $base.".xmp" ) {
                    $xmpfilename = $base.".xmp";
                }
                elsif( -e $base.".XMP" ) {
                    $xmpfilename = $base.".XMP";
                }
            }
            # --- XMP file already exist, merge ------------------------------
            if( $xmpfilename ) {
                print STDERR "[ID='$id'] Update '$xmpfilename'\n";
                if( $dump_xmp ) {
                    $exifTool->WriteInfo( $xmpfilename, '-', 'XMP' ) or die $exifTool->GetValue('Error');
                }
                unless( $dryrun ) {
                    $exifTool->WriteInfo( $xmpfilename ) or die $exifTool->GetValue('Error');
                }
            }
            # --- No XMP file, create new ------------------------------------
            else {
                my $base = strip_suffix($$version[3]);
                $xmpfilename = $base.".xmp";
                print STDERR "[ID='$id'] Create '$xmpfilename'\n";

                if( $dump_xmp ) {
                    $exifTool->WriteInfo( undef, '-', 'XMP' ) or die $exifTool->GetValue('Error');
                }

                unless( $dryrun ) {
                    $exifTool->WriteInfo( undef, $xmpfilename, 'XMP' ) or die $exifTool->GetValue('Error');
                }
            }
        }

        $photos_processed++;
        #if( $photos_processed > 200 ) {
        #    last;
        #}
    }
    $sth->finish();
}
$dbh->disconnect;
