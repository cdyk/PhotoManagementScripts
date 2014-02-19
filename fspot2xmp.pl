#!/usr/bin/perl -W

use strict;
use DBI;
use 5.010;      # we use smart match

# CREATE TABLE photos (
#   id			INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, 
#	time			INTEGER NOT NULL, 
#	base_uri		STRING NOT NULL, 
#	filename		STRING NOT NULL,        # Contains original (CR2-file)
#	description		TEXT NOT NULL, 
#	roll_id			INTEGER NOT NULL, 
#	default_version_id	INTEGER NOT NULL, 
# 	rating			INTEGER NULL 
# );
#CREATE TABLE photo_versions (
#	photo_id	INTEGER,                    # references photos
#	version_id	INTEGER, 
#	name		STRING,                     # Original Jpeg
#	base_uri		STRING NOT NULL, 
#	filename		STRING NOT NULL, 
#	import_md5		TEXT NULL, 
#	protected	BOOLEAN, 
#	UNIQUE (photo_id, version_id)
#);
# CREATE INDEX idx_photo_versions_import_md5 ON photo_versions(import_md5);
# CREATE TABLE tags (
# 	id		INTEGER PRIMARY KEY NOT NULL, 
#	name		TEXT UNIQUE, 
#	category_id	INTEGER, 
#	is_category	BOOLEAN, 
#	sort_priority	INTEGER, 
#	icon		TEXT
#);
#CREATE TABLE photo_tags (
#	photo_id	INTEGER, 
#       tag_id		INTEGER, 
#       UNIQUE (photo_id, tag_id)
#);
my $dryrun  = 1;
my $db_path = "photos.db"; #"$ENV{'HOME'}/.config/f-spot/photos.db";

sub print_help {
        print STDERR "Recognized options:\n";
        print STDERR "    --help    This help\n";
        print STDERR "    --dryrun  Don't actually write anything.\n";
        print STDERR "    --db path Specify path to F-Spot database.\n";
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
    else {
        print STDERR "Unrecognized option '$arg'\n\n";
        print_help();
        die;
    }
}

# Check if db file exist
unless( -e $db_path ) {
    print "Db path '$db_path' does not exist.\n";
    die;
}

# Check if SQLite is available
unless( "SQLite" ~~ [DBI->available_drivers()] ) {
    print "DBI is missing the SQLite driver, available drivers:\n";
    print join("\n", DBI->available_drivers()), "\n";
    die;
}

my $dbh = DBI->connect( "dbi:SQLite:$db_path" ) or die $DBI::errstr;


# --- Create tag hierarchies -------------------------------------------------
my %tags;
{   
    my $sth = $dbh->prepare( "SELECT id, name, category_id FROM tags" ) or die $DBI::errstr;
    $sth->execute();
    while( my ($id, $name, $category_id) = $sth->fetchrow_array() ) {
        $tags{$id} = [$name, $category_id, [] ];
    }
    $sth->finish();

    # traverse hierarchy
    foreach my $id (keys %tags) {
        my $category = $tags{$id}[1];
        while( $category ) {
            push @{$tags{$id}[2]}, $tags{$category}[0];
            $category = $tags{$category}[1];
        }

        print $id, ":", $tags{$id}[0], ":", join( ", ", @{$tags{$id}[2]} ), "\n";
    }
}

# --- Plow through photos ----------------------------------------------------
if(0) {   
    my $sth = $dbh->prepare( "SELECT id, base_uri, filename FROM photos" ) or die $DBI::errstr;
    $sth->execute();
    while( my ($id, $base_uri, $filename ) = $sth->fetchrow_array() ) {

        # get tags of this photo
        my $tags = $dbh->selectcol_arrayref( "SELECT tag_id ".
                                             "FROM photo_tags ".
                                             "WHERE photo_id='$id'" )  or die $DBI::errstr;
        #print join( ", ", $id, $base_uri, $filename ), "tags: ", join( ", ", @{$sub_sth} ), "\n";
    }
    $sth->finish();
}
$dbh->disconnect;

