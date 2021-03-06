#!/nfs/disk100/wormpub/bin/perl -w
# update_web_gene_names.pl
#
# completely rewritten by Keith Bradnam from list_loci_designations
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2010-07-14 14:18:41 $
#
# This script should be run under a cron job and simply update the webpages that show
# current gene names and sequence connections.  Gets info from geneace.  

use strict;
use lib $ENV{'CVS_DIR'};
#use lib '/nfs/disk100/wormpub/lib/perl5/site_perl/5.8.7';
use Wormbase;
use Ace;
use Carp;
use Getopt::Long;
use Storable;

##############################
# Command line options       #
##############################

my $store;
my $file;

#changed the cmd line opts to relect what goes on - left variables the same -ar2

GetOptions (
	    		"store:s"      => \$store,	
	   		"file:s"       => \$file
	   );

my $wormbase;
if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( );
}

my $log = Log_files->make_log("/tmp/update_web_gene_names");

##############################
# Script variables (run)     #
##############################

my $tace  = $wormbase->tace;
my $www = "/nfs/WWWdev/SANGER_docs/htdocs/Projects/C_elegans/LOCI"; # where output will be going

my $rundate = $wormbase->rundate;
my $database;



# Set up log file

my ($sec,$min,$hour,$mday,$mon,$year, $wday,$yday,$isdst) = localtime time;
$year += 1900;
$year += 1;
my $date = "$year-$mon-$mday";

# make the a-z lists based on CGC_name using current_DB
$log->write_to("Creating loci pages based on current_DB\n");
&create_currentDB_loci_pages;

# make lists of gene2molecular_name and molecular_name2gene
$log->write_to("Making daily update lists\n");
&make_gene_lists;

###################################################
# Tidy up - close things, mail log, run webpublish
###################################################

# now update pages using webpublish
chdir($www) || print LOG "Couldn't run chdir\n";


$wormbase->run_command("/software/bin/webpublish -q *.shtml", $log) && $log->write_to("Couldn't run webpublish on html files\n");
$wormbase->run_command("/software/bin/webpublish -q *.txt", $log) && $log->write_to("Couldn't run webpublish on text file\n");

$log->write_to("check http://www.sanger.ac.uk/Projects/C_elegans/LOCI/genes2molecular_names.txt is up to date\n");


##################
# Check the files
##################
  $wormbase->check_file("$www/loci_all.txt", $log,
                  minsize => 600000);
  foreach my $letter ("a".."z") {
    $wormbase->check_file("$www/loci_designations_${letter}.shtml", $log,
			  minsize => 1000);
  }
  $wormbase->check_file("$www/genes2molecular_names.txt", $log,
                  minsize => 700000);

  $wormbase->check_file("$www/molecular_names2genes.txt", $log,
                  minsize => 600000);


$log->mail;
exit(0);




#######################################################################################
#
#                    T  H  E    S  U  B  R  O  U  T  I  N  E  S
#
#######################################################################################


sub create_currentDB_loci_pages{

  # query against current_DB
  $database = $wormbase->database('current');
  my $db = Ace->connect(-path  => "$database",
                       -program =>$tace) or $log->log_and_die("Connection failure: ".Ace->error);


  # open text file which will contain all genes
  open (TEXT, ">$www/loci_all.txt") or $log->log_and_die("Couldn't open text file for writing to\n");
  print TEXT "Gene name, WormBase gene ID, Gene version, CDS name (Wormpep ID), RNA gene name, pseudogene name, other names, approved?\n";

  foreach my $letter ("a".."z") {
    # Get all Loci
    my @gene_names = $db->fetch(-query=>"Find Gene_name $letter\* WHERE Public_name_for");
    
    # loop through each file (one for each letter a-z)
    open (HTML, ">$www/loci_designations_${letter}.shtml") || croak "Couldn't open file for writing to $www/loci_designations_${letter}.shtml\n";
    system("touch $www/loci_${letter}.shtml"); # this just updates the footer date on the webpage :)
    my $line = 0;

    # cycle through each locus in database
    foreach my $gene_name (@gene_names) {


      # skip gene names that are just sequence names
      next unless ($gene_name->CGC_name_for || $gene_name->Other_name_for);

      # need to get Gene object via CGC_name_for or Other_name_for tags
      my $gene;
      my $public_name;

      if ($gene_name->CGC_name_for) {
	$gene = $gene_name->CGC_name_for;
	$public_name = $gene->CGC_name;
      } else {
	$gene = $gene_name->Other_name_for;
	$public_name = $gene->Other_name;
      }
      
      # ignore non C. elegans genes for now
      my $species = $gene->Species;
      next unless ($species eq "Caenorhabditis elegans");

      # ignore dead genes
      next if($gene->Status->name ne "Live");

      # Set alternating colours for each row of (HTML) output 
      if (($line % 2) == 0) { 
	print HTML "<TR BGCOLOR=\"lightblue\">\n";
      } else {
	print HTML "<TR BGCOLOR=\"white\">\n";
      }
      
      # Column 1 - ?Gene name
      print HTML "<TD align=center><A HREF=\"http://www.wormbase.org/db/gene/gene?name=${public_name}\">${public_name}</a></TD>";
      print TEXT "$public_name,";
      
      
      # Column 2 - Gene ID
      print HTML "<TD align=center><A HREF=\"http://www.wormbase.org/db/gene/gene?name=${gene};class=Gene\">${gene}</a></TD>";
      print TEXT "$gene,";
      
      # Column 3 - Gene Version
      my $version = $gene->Version;
      print HTML "<TD align=center>$version</TD>";
      print TEXT "$version,";
      
      # Column 4 - ?CDS connections
      if (defined($gene->at('Molecular_info.Corresponding_CDS'))) {
	my @CDSs = $gene->Corresponding_CDS;
	print HTML "<TD>";
	foreach my $cds (@CDSs) {
	  # also get wormpep identifier for each protein
	  my $protein = $cds->Corresponding_protein;
	  print HTML "<A HREF=\"http://www.wormbase.org/db/gene/gene?name=${cds};class=CDS\">${cds}</a> ";
	  print HTML "(<A HREF=\"http://www.wormbase.org/db/seq/protein?name=${protein};class=Protein\">${protein}</a>) ";
	  print TEXT "$cds ($protein) ";
	}
	print TEXT ",,,";
	print HTML "</TD><TD>&nbsp</TD><TD>&nbsp</TD>";
      }
      
      
      # Column 5 - ?Transcript connections
      elsif (defined($gene->at('Molecular_info.Corresponding_transcript'))) {
	print HTML "<TD>&nbsp</TD>";
	my @transcripts = $gene->Corresponding_transcript;
	print HTML "<TD>";
	print TEXT ",";
	foreach my $i (@transcripts) {
	  print HTML "<A HREF=\"http://www.wormbase.org/db/seq/sequence?name=${i}\">${i}</a> ";
	  print TEXT "$i ";
	}
	print TEXT ",,";
	print HTML "</TD><TD>&nbsp</TD>";
      }
      
      # Column 6 - ?Pseudogene connections
      elsif (defined($gene->at('Molecular_info.Corresponding_pseudogene'))) {
	my @pseudogenes = $gene->Corresponding_pseudogene;
	print HTML "<TD>&nbsp</TD><TD>&nbsp</TD><TD>";
	print TEXT ",,";
	foreach my $i (@pseudogenes) {
	  print HTML "<A HREF=\"http://www.wormbase.org/db/seq/sequence?name=${i}\">${i}</a> ";
	  print TEXT "$i ";
	}
	print HTML "</TD>";
	print TEXT ",";
      }
      
      # Blank columns if no ?Sequence, ?Transcript, or ?Pseudogene
      else {
	print HTML "<TD>&nbsp</TD><TD>&nbsp</TD><TD>&nbsp</TD>";
	print TEXT ",,,";
      }
      
      
      # Column 7 - Other names for ?Gene
      if (defined($gene->at('Identity.Name.Other_name'))) {
	my @other_names = $gene->Other_name;
	print HTML "<TD>";
	foreach my $i (@other_names) {
	  print HTML "${i} ";
	  print TEXT "$i ";
	}
	print HTML "</TD>";
      } else {
	print HTML "<TD>&nbsp</TD>";
      }
      print TEXT ",";
      
      
      # Column 8 CGC approved?
      if (defined($gene->at('Identity.Name.CGC_name'))) {
	print HTML "<TD align=center>approved</TD>\n";
	print TEXT "approved"
      } else {
	print HTML"<TD>&nbsp<TD>\n";
      }
      
      $line++;
      print HTML "</TR>\n";
      print TEXT "\n";
      $gene->DESTROY();
    }
  }
  print TEXT "last updated $date (YYYY-MM-DD)\n";
  close(TEXT);

  $db->close;
}


############################################################

sub make_gene_lists{

  my %molecular_name2gene;
  my %gene2molecular_name;
  
  if ($file) {	
  	open (TACE,"<$file") or $log->log_and_die("cant open $file");
  }	
  else {
  	# connect to AceDB using TableMaker, 
  	my $autoace = $wormbase->autoace;
 	my $command="Table-maker -p $autoace/wquery/gene2molecular_name.def\nquit\n";
  	open (TACE, "echo '$command' | $tace $autoace |") || print LOG "ERROR: Can't open tace connection to $autoace\n";
  }
  while (<TACE>) {
    chomp;
    # skip any acedb banner text (table maker output has all fields surrounded by "")
    next if ($_ !~ m/^\"/);  #" for syntax highlight
    # skip acedb prompts
    next if (/acedb/);
    # skip empty fields
    next if ($_ eq "");
                                                                                           
    # get rid of quote marks
    s/\"//g;
                                                                                           
    # split the line into various fields
    my ($gene,$sequence_name,$cgc_name) = split(/\t/, $_) ;

    # populate hashes, appending CGC name if present
    if (defined($cgc_name)) {
      $molecular_name2gene{$sequence_name} = "$gene $cgc_name";
      $gene2molecular_name{$gene} = "$sequence_name $cgc_name";
    } else {
      $molecular_name2gene{$sequence_name} = $gene;
      $gene2molecular_name{$gene} = $sequence_name;
    }
  }
  close TACE;


  # set up various output files (first two are reverse of each other)


  open (GENE2MOL, ">$www/genes2molecular_names.txt") or $log->log_and_die("ERROR: Couldn't open genes2molecular_names.txt  $!\n");
  foreach my $key (sort keys %gene2molecular_name){

    print GENE2MOL "$key\t$gene2molecular_name{$key}\n";	      
  }
  print GENE2MOL "last updated $date (YYYY-MM-DD)\n";
  close(GENE2MOL);


  open (MOL2GENE, ">$www/molecular_names2genes.txt") || die "ERROR: Couldn't open molecular_names2genes.txt $!\n";
  foreach my $key (sort keys %molecular_name2gene){
    print MOL2GENE "$key\t$molecular_name2gene{$key}\n";
  }
  print MOL2GENE "last updated $date (YYYY-MM-DD)\n";
  close(MOL2GENE);
}



__END__

=pod

=head1 NAME - update_web_gene_names.pl

=back

=head1 USAGE

=over 4

=item update_web_gene_names.pl 

Simply takes the latest set of gene names in geneace and writes to the development web site
a set of HTML pages (one for each letter of the alphabet) containing all gene names starting
with that letter.  Makes these tables hyperlinked to WormBase and also includes other names
and CDS (with wormpep)/transcript/pseudogene connections.  Also includes Gene IDs and 
version numbers as extra columns.

Additionally makes two other files which is just gene 2 molecular name and vice versa.

When script finishes it copies across to the live web site.  This script should normally be
run every night on a cron job for the genes2molecular_names.txt file and weekly for the a-z pages.

=back

=head2 camcheck.pl MANDATORY arguments:

=over 4

=item none

=back

=head2 camcheck.pl OPTIONAL arguments:

=over 4

=back


=head1 AUTHOR - Keith Bradnam

Email krb@sanger.ac.uk

=cut
