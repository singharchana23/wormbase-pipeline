#!/usr/local/bin/perl5.8.0 -w
#
# script_template.pl
#
# by Keith Bradnam
#
# This is a example of a good script template
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2008-07-23 12:16:43 $

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;

######################################
# variables and command-line options #
######################################

my ( $help, $debug, $test, $verbose, $store, $wormbase, $species );

GetOptions(
    'help'      => \$help,
    'debug=s'   => \$debug,
    'test'      => \$test,
    'verbose'   => \$verbose,
    'store:s'   => \$store,
    'species:s' => \$species,
);

if ($store) {
    $wormbase = retrieve($store) or croak("Can't restore wormbase from $store\n");
} 
else {
    $wormbase = Wormbase->new(
        -debug => $debug,
        -test  => $test,
	-organism => $species,
    );
}

# Display help if required
&usage('Help') if ($help);

# in test mode?
print "In test mode\n" if ( $verbose && $test );

# establish log file.
my $log = Log_files->make_build_log($wormbase);

#################################
# Set up some useful paths      #
#################################

# Set up top level base directories (these are different if in test mode)
my $gff_dir = $wormbase->gff;    # GFF
my $ace_dir = $wormbase->autoace;# Autoace

# other paths
my $tace = $wormbase->tace;      # TACE PATH

###################################
# get the species of the sequences
###################################

my $cmd1 = "Query Find Sequence Where Database = \"NEMATODE_NET\"\nshow -a Species\nquit";
my $cmd2 = "Query Find Sequence Where Database = \"NEMBASE\"\nshow -a Species\nquit";
my $cmd3 = "Query Find Sequence Where Database = \"EMBL\"\nshow -a Species\nquit";

my %species;
my ( $id, $db );

print "Finding BLAT_WASHU data\n";
open( TACE, "echo '$cmd1' | $tace $ace_dir |" );
while (<TACE>) {
    chomp;
    next if (/acedb\>/);
    next if (/\/\//);
    if (/Sequence\s+:\s+\"(\S+)\"/) {
        $id = $1;
    }
    elsif (/Species\s+\"(.+)\"/) {
        $species{'BLAT_WASHU'}->{$id} = $1;
    }
}
close TACE;

print "Finding BLAT_NEMBASE data\n";
open( TACE, "echo '$cmd2' | $tace $ace_dir |" );
while (<TACE>) {
    chomp;
    next if (/acedb\>/);
    next if (/\/\//);
    if (/Sequence\s+:\s+\"(\S+)\"/) {
        $id = $1;
    }
    elsif (/Species\s+\"(.+)\"/) {
        $species{'BLAT_NEMBASE'}->{$id} = $1;
    }
}
close TACE;

print "Finding BLAT_NEMATODE data\n";
open( TACE, "echo '$cmd3' | $tace $ace_dir |" );
while (<TACE>) {
    chomp;
    next if (/acedb\>/);
    next if (/\/\//);
    if (/Sequence\s+:\s+\"(\S+)\"/) {
        $id = $1;
    }
    elsif (/Species\s+\"(.+)\"/) {
        $species{'BLAT_NEMATODE'}->{$id} = $1;
    }
}
close TACE;

##########################
# MAIN BODY OF SCRIPT
##########################
my $count;

# loop through the chromosomes
my @chromosomes = $wormbase->get_chromosome_names( -mito => 1, -prefix => 1 );
foreach my $chromosome (@chromosomes) {
    print "Reading $chromosome\n" if ($verbose);

    # loop through the GFF file
    my @f;

    # filename munging
    my $GFF_file_name = $wormbase->GFF_file_name($chromosome, undef);
    my $new_file = "${GFF_file_name}.new";

    # We don't use the $wormbase->open_GFF_file method when dealing
    # with species with genomes in many contigs because it is
    # inefficient to read in the same file thousands of times when we
    # can process all of the lines in one read-through as we don't
    # care which chromosome the BLAT match is to.
    # 
    # my $gffinf = $wormbase->open_GFF_file($chromosome, undef, $log); 

    open (GFFINF, "<$GFF_file_name") || die "Can't open $GFF_file_name\n"; 
    open(OUT, ">$new_file") || die "Failed to open gff file $new_file\n";

    while ( my $line = <GFFINF> ) {
        chomp $line;
        if ( $line =~ /^#/ || $line !~ /\S/ ) {
            print OUT "$line\n";
            next;
        }
        @f = split /\t/, $line;
        my $id;

	# It is possible that this script is being run on the same
	# input file multiple times (e.g. when sorting out problems)
	# in which case we do not want to add 'Species' multiple
	# times to the same line.
	if (defined $f[8] && $f[8] !~ /;\sSpecies/) {


	  # is this a BLAT_WASHU or BLAT_NEMBASE or BLAT_NEMATODE or BLAT_Caen_EST_* line?
	  if ( $f[1] eq 'BLAT_WASHU' ) {

				# get the ID name
            ($id) = ( $f[8] =~ /Target \"Sequence:(\S+)\"/ );

            if ( exists $species{'BLAT_WASHU'}->{$id} ) {
	      $line = $line . " ; Species \"" . $species{'BLAT_WASHU'}->{$id} . "\"";
	      $count++;
	      print "$line\n" if ($verbose);
            }
	  }
	  elsif ( $f[1] eq 'BLAT_NEMBASE' ) {

				# get the ID name
            ($id) = ( $f[8] =~ /Target \"Sequence:(\S+)\"/ );

            if ( exists $species{'BLAT_NEMBASE'}->{$id} ) { # 
	      $line = $line . " ; Species \"" . $species{'BLAT_NEMBASE'}->{$id} . "\"";
	      $count++;
	      print "$line\n" if ($verbose);
            }
	  }
	  elsif ( $f[1] eq 'BLAT_NEMATODE' ) {

				# get the ID name
            ($id) = ( $f[8] =~ /Target \"Sequence:(\S+)\"/ );

            if ( exists $species{'BLAT_NEMATODE'}->{$id} ) {
	      $line = $line . " ; Species \"" . $species{'BLAT_NEMATODE'}->{$id} . "\"";
	      $count++;
	      print "$line\n" if ($verbose);
            }
            else {
	      #print "BLAT_NEMATODE species doesn't exist for $id\n";
            }
	  }
	  elsif ( $f[1] =~ /BLAT_Caen_EST_/ ){    # BLAT_Caen_EST_BEST or BLAT_Caen_EST_OTHER
				# get the ID name
            ($id) = ( $f[8] =~ /Target \"Sequence:(\S+)\"/ );

            if ( exists $species{'BLAT_NEMATODE'}->{$id} ) # 
            { # the {'BLAT_NEMATODE'} hash holds the EMBL data which BLAT_Caen_EST_* uses as well
	      $line = $line . " ; Species \"" . $species{'BLAT_NEMATODE'}->{$id} . "\"";
	      $count++;
	      print "$line\n" if ($verbose);
            }
            else {
	      print "BLAT_Caen_EST species doesn't exist for $id\n";
            }
	  }
	}

        # write out the line
        print OUT "$line\n";

        # end of GFF loop
    }

    # close files
    close(GFFINF);
    close(OUT);

    # copy new GFF files over
    system("mv -f $new_file $GFF_file_name");

    # If we are dealing with a species with genomes in many contigs
    # and all the GFF data in one file, it is inefficient to read in
    # the same file thousands of times when we have processed all of
    # the lines in the first read-through as we don't care or test
    # which chromosome the BLAT match is to.
    if (! $wormbase->separate_chromosomes) {last}

}    # chromosome loop

# Close log files and exit
$log->write_to("\n\nStatistics\n");
$log->write_to("----------\n\n");
$log->write_to("Changed $count lines\n");

##################
# Check the files
##################
$wormbase->check_files($log); 

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

    if ( $error eq "Help" ) {

        # Normal help menu
        system( 'perldoc', $0 );
        exit(0);
    }
}

##########################################

# Add perl documentation in POD format
# This should expand on your brief description above and
# add details of any options that can be used with the program.
# Such documentation can be viewed using the perldoc command.

__END__

=pod

=head2 NAME - add_species_to_BLAT_GFF.pl

=head1 USAGE

=over 4

=item  add_species_to_BLAT_GFF.pl [-options]

=back

Todd wanted to have species names added to the GFF results for non-elegans EST BLAT hits.
This script gets the species for each EST sequence from the autoace database and adds this information to the GFF records.

script_template.pl MANDATORY arguments:

=over 4

=item None at present.

=back

script_template.pl  OPTIONAL arguments:

=over 4

=item -h, Help

=back

=over 4
 
=item -debug, Debug mode, set this to the username who should receive the emailed log messages. The default is that everyone in the group receives them.
 
=back

=over 4

=item -test, Test mode, run the script, but don't change anything.

=back

=over 4
    
=item -verbose, output lots of chatty test messages

=back


=head1 REQUIREMENTS

=over 4

=item None at present.

=back

=head1 AUTHOR

=over 4

=item Gary Williasm (gw3@sanger.ac.uk)

=back

=cut
