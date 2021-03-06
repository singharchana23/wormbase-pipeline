#!/usr/local/bin/perl5.8.0 -w
#
# new_wormpep_entries.pl
#
# by Keith Bradnam
#
# Script to find new wormpep entries in the last release of wormpep
# and produce a fasta file of these sequence to load into the wormprot
# mysql database prior for the pre-build pipeline.
#
# Last updated by: $Author: ar2 $
# Last updated on: $Date: 2007-05-23 13:33:11 $


#################################################################################
# variables                                                                     #
#################################################################################

use strict;                                      
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;
use IO::Handle;
use Cwd;

######################################
# variables and command-line options # 
######################################

my ($help, $debug, $test, $verbose, $store, $wormbase);


GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"    => \$store,
	    );

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
			     );
}

# Display help if required
&usage("Help") if ($help);

# in test mode?
if ($test) {
  print "In test mode\n" if ($verbose);

}

# establish log file.
my $log = Log_files->make_build_log($wormbase);


 ##############################
 # Script variables (run)     #
 ##############################

my $release = $wormbase->get_wormbase_version; 
my $old_release = $release - 1;
my $release_name = $wormbase->get_wormbase_version_name; 


##########################################
# Set up database paths                  #
##########################################

# Set up top level base directory which is different if in test mode
# Make all other directories relative to this
my $basedir         = $wormbase->wormpep;     # BASE DIR => changed to WB->wormpep


# need to get previous build WORMPEP
my $PEP_FILE_STEM = $wormbase->pepdir_prefix . "pep"; #wormpep
my $PEP_PREFIX    = $wormbase->pep_prefix;#CE
$basedir =~ /(.*)(\d{3})$/;
my $wpdir =  $1 . ($2 - 1);

# briggsae part 1
our $dbfile     = "$basedir/${PEP_FILE_STEM}.fasta${release}";
our $old_dbfile = "$wpdir/${PEP_FILE_STEM}.fasta${old_release}";

# make a hash of wormpep IDs -> peptide sequence for current and previous versions
# of wormpep
our %wormpep;
our %old_wormpep;
&make_hash;
&make_old_wormpep_hash;

# Simple but important check...is the new wp.fasta file bigger than the old one.
# if not then this is serious and should be investigated
my $old_wp_size = keys(%old_wormpep);
my $new_wp_size = keys(%wormpep);


if($old_wp_size > $new_wp_size){
  $log->log_and_die("ERROR: WS${release} wp.fasta file appears to have fewer entries than WS${old_release} wp.fasta file!\n\n");
}

my %proteins_outputted;
 ###############################
 # Main Loop                   #
 ###############################


# briggsae part2
open (NEW,  ">$basedir/new_entries.$release_name") || $log->log_and_die( "Couldn't write output file\n");
open (DIFF, "<$basedir/wormpep.diff${release}") || $log->log_and_die( "Couldn't read from diff file\n");
my $new_count =0;
while (<DIFF>) {    
  my ($new_acc,$seq);
    if( (/changed:\t\S+\s+\S+ --> (\S+)/) || (/new:\t\S+\s+(\S+)/) || (/reappeared:\t\S+\s+(\S+)/)) {
      $new_acc = $1;
      next if $old_wormpep{$new_acc};
      next if $proteins_outputted{$new_acc};
      print NEW ">$new_acc\n$wormpep{$new_acc}";
      $proteins_outputted{$new_acc}++;
      $new_count++;
    }
}
close(DIFF);
close(NEW);

$log->write_to("written $new_count new proteins to file\n");
$log->mail();
print "Finished.\n" if ($verbose);
exit(0);


##############################################################
#
# Subroutines
#
##############################################################



##########################################

sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

##########################################
#
# more briggsae prefix things

sub make_hash {
  my $id;
  my $seq;
  my $prefix=$wormbase->pep_prefix;
  open (WP, "<$dbfile") || $log->log_and_die( "Couldn't read from file\n");
  while (<WP>) {
    if (/^>(\S+)/) {
      chomp;
      my $new_id = $1;
      if ($id) {
	$id =~ /${prefix}0*([1-9]\d*)/ ; 
	$wormpep{$id} = $seq;
      }
      $id = $new_id ; $seq = "" ;
    } 
    elsif (eof) {
      if ($id) {
	$id =~ /${prefix}0*([1-9]\d*)/ ;
	$seq .= $_ ;
	$wormpep{$id} = $seq;
      }
    } 
    else {
      $seq .= $_ ;
    }
  }

  close (WP);
  
}
#################################

sub make_old_wormpep_hash {
  my $id;
  my $seq;
  my $prefix=$wormbase->pep_prefix;

  open (WP, "<$old_dbfile") || $log->log_and_die( "Couldn't read from file $old_dbfile :$! \n");
  while (<WP>) {
    if (/^>(\S+)/) {
      chomp;
      my $new_id = $1;
      if ($id) {
	$id =~ /${prefix}0*([1-9]\d*)/ ; 
	$old_wormpep{$id} = $seq;
      }
      $id = $new_id ; $seq = "" ;
    } 
    elsif (eof) {
      if ($id) {
	$id =~ /${prefix}0*([1-9]\d*)/ ;
	$seq .= $_ ;
	$old_wormpep{$id} = $seq;
      }
    } 
    else {
      $seq .= $_ ;
    }
  }

  close (WP);
  
}


exit(0);


__END__

=pod

=head1 NAME - new_wormpep_entries.pl

=head2 USAGE

This file looks at the wormpep.diff file from the current release of
wormpep and extracts any new peptide sequences which it writes to
a file inside the respective wormpep directory.  This fasta file
is needed by the prebuild process to populate the wormprot mysql
database with the new protein entries.

More specifically, this script looks for genes flagged as 'new',
'changed', or 'reappeared' in the wormpep.diff file.  However, The 
latter two categories may represent genes that have a wormpep protein 
which already exists. In this sense, we don't need to output the protein 
because it will already be in the MySQL database.  This script always 
compares proteins to the wp.fasta file from the previous release, so
if it spots an older CExxxxx identifier it doesn't bother dumping
the sequence as a 'new' protein.
 
Optional arguments:

=over 4

=item *

-h  this help

=back

=cut
