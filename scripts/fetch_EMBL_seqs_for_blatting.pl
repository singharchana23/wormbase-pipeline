#!/usr/local/bin/perl5.8.0 -w
#
# fetch_EMBL_seqs_for_blatting.pl
#
# by Keith Bradnam
# 
# Attempt to unify all of the diverse scripts to fetch ESTs, OSTs, mRNAs etc. used by blat 
#
# Last edited by: $Author: krb $
# Last edited on: $Date: 2003-09-11 13:26:18 $

use strict;
use lib "/wormsrv2/scripts/";
use Wormbase;
use Getopt::Long;
use Data::Dumper;


##############################
# command-line options       #
##############################

my $help;                # Help/Usage page
my $ace;                 # Dump acefile
my $verbose;             # turn on extra output
my $blastdb;             # make blast database using pressdb?
my $ftp;                 # also copy to ftp site
my $debug;               # For sending output to just one person
my $maintainers = "All"; # log file recipients
my ($est, $mrna, $ost, $nematode, $embl); # the main options


GetOptions (
	    "ace"      => \$ace,
	    "est"      => \$est,
	    "mrna"     => \$mrna,
	    "ost"      => \$ost,
	    "nematode" => \$nematode,
	    "embl"     => \$embl,
	    "verbose"  => \$verbose,
	    "blastdb"  => \$blastdb,
	    "ftp"      => \$ftp,
	    "debug"    => \$debug,
            "help"     => \$help
	    );

# Help pod if needed
&usage(0) if ($help);

# Use debug mode?
if($debug){
  print "DEBUG = \"$debug\"\n\n";
  ($maintainers = $debug . '\@sanger.ac.uk');
}

##############################
# Other script variables     #
##############################

my $acc;                 # EMBL accession
my $id;                  # EMBL ID   
my $sv;                  # EMBL sequence version
my $def = "";            # EMBL description, needs to be initialised to ""
my $protid;              # EMBL Protein_ID
my $protver;             # EMBL Protein_ID version
my $org;                 # EMBL species

my $ost_seq;             # tag for OST/EST split
my %EST_name;            # EST accession => name
my %EST_dir;             # EST accession => orientation [5|3]

my $log;                 # for log file
 
my $dir    = "/nfs/disk100/wormpub/analysis/ESTs"; # path for output files
my $ftpdir = "/nfs/disk69/ftp/pub/wormbase/sequences/ESTS"; # path for ftp site
my $getz   = "/usr/local/pubseq/bin/getzc"; # getz binary



#########################################
#
# M A I N   P A R T   O F   S C R I P T
#
#########################################

&create_log_files;
&make_ests          if ($est || $ost);
&make_mrnas         if ($mrna);
&make_embl_cds      if ($embl);
&make_nematode_ests if ($nematode);


# Tidy up things and exit

print LOG "finished at ",&runtime,"\n";
&mail_maintainer("script template",$maintainers,$log);
close(LOG);

exit(0);


exit(0);


########################################################################
#
# Subroutines
#
#########################################################################



#################################################
#
# C. elegans ESTs and OSTs
#
#################################################

sub make_ests{

  print LOG "Fetching EST sequences\n" if ($est);
  print LOG "Fetching OST sequences\n" if ($ost);

  # read accession->yk name hash for EST names 
  open (FH, "</wormsrv2/autoace/BLAT/EST.dat") or die "EST.dat : $!\n";
  undef $/;
  my $data = <FH>;
  eval $data;
  die if $@;
  $/ = "\n";
  close(FH);

  # OSTs are actually a subset of ESTs in EMBL, will usually want both
  open (OUT_EST, ">$dir/elegans_ESTs")     if ($est);
  open (OUT_OST, ">$dir/elegans_OSTs")     if ($ost);
  open (OUT_ACE, ">$dir/elegans_ESTs.ace") if ($ace);

  # grab everything which is C. elegans species in EST division of EMBL (=emblrelease + emblnew)
  open (SEQUENCES, "$getz -sf fasta -f \"id acc des seq sv\" \'([embl-org:caenorhabditis elegans] \& [embl-div:est])\' |") ;

  while (<SEQUENCES>) {

    unless (/^AC\s+/ || /^DE\s+/ || /^>/ || /^ID\s+/ || /^SV\s+/) {
      print OUT_EST  if ($ost_seq == 0);
      print OUT_ACE  if (($ost_seq == 0) && ($ace));
      print OUT_OST  if ($ost_seq == 1);      
    }
    
    # grab accession, id, sequence version, and description
    ($acc = $1) if (/^AC\s+(\S+);/);
    ($id = $1) if (/^ID\s+(\S+)/);
    ($sv = $1) if (/^SV\s+\S+\.(\d+)/);

    if (/^DE\s+(.+)/)   {
      $def = $def." ".$1;
      
      if ($def =~ /^ OST/) {
	$ost_seq = 1;
      }
      else {
	$ost_seq = 0;
      }
    }
    if (/^>/) {
      if ($ost_seq == 0) {
	print OUT_EST ">$acc $id $def\n";
	
	if ($ace) {
	  if (exists $EST_name{$acc}) {
	    print OUT_ACE "\nSequence : \"$EST_name{$acc}\"\nDatabase EMBL $id $acc $sv\n";
	  }
	  else {	
	    print OUT_ACE "\nSequence : \"$acc\"\nDatabase EMBL $id $acc $sv\n";
	  }
	  print OUT_ACE   "Species \"Caenorhabditis elegans\"\n";
	  print OUT_ACE   "Title \"$def\"\nMethod EST_elegans\n";
	  
	  if (exists $EST_name{$acc}) {
	    print OUT_ACE "\nDNA \"$EST_name{$acc}\"\n" if ($ace);
	  }
	  else {	
	    print OUT_ACE   "\nDNA \"$acc\"\n" if ($ace);
	  }
	}
	# reset variables
	$def = "";
	$id  = "";
	$sv  = "";
	$acc = "";
      } 
      else {
	# treat OSTs slightly differently, no need for acefile
	print OUT_OST ">$acc $id $def\n";
	$def = "";
	$id  = "";
	$sv  = "";
	$acc = "";
      }
    }
  }
  # close file handles
  close (SEQUENCES);
  close (OUT_EST) if ($est);
  close (OUT_OST) if ($ost);
  close (OUT_ACE) if ($ace);

  # make blast database?
  if($blastdb){
    print LOG "Making blast databases\n";
    system ("/usr/local/pubseq/bin/pressdb $dir/elegans_ESTs > /dev/null") if ($est);
    system ("/usr/local/pubseq/bin/pressdb $dir/elegans_OSTs > /dev/null") if ($ost);
  }

  # push to ftp site?
  if($ftp){
    print LOG "Copying file to FTP site\n";
    if($est){
      system ("/bin/rm -f $ftpdir/elegans_ESTs.gz");
      system ("cp $dir/elegans_ESTs $ftpdir/elegans_ESTs");
      system ("/bin/gzip $ftpdir/elegans_ESTs");
    }
    if($ost){
      system ("/bin/rm -f $ftpdir/elegans_OSTs.gz");
      system ("cp $dir/elegans_ESTs $ftpdir/elegans_OSTs");
      system ("/bin/gzip $ftpdir/elegans_OSTs");
    }
  }

}



#################################################################
#
# C. elegans mRNAs
#
#################################################################

sub make_mrnas{

  print LOG "Fetching mRNA sequences\n";

  # open filehandles for output files 
  open (OUT_MRNA, ">$dir/elegans_mRNAs");
  open (OUT_ACE,  ">$dir/elegans_mRNAs.ace") if ($ace);

  # Grab all RNA sequences (mRNA, pre-mRNA, unassigned RNA, and other RNA) from C. elegans sequences which are not in 
  # EST division from EMBL (= emblrelease + emblnew)
  open (SEQUENCES, "$getz -f \"acc\" \'([embl-org:Caenorhabditis elegans] & [embl-mol:*rna] ! [embl-div:EST])\' |") ;

  while (<SEQUENCES>) {
    chomp;
    ($acc) = (/^AC\s+(\S+)\;/);
    print "Parsing EMBL accession: '$acc'\n" if ($verbose);
    next if ($acc eq "");

    # pfetch each sequence individually
    open (LOOK, "/usr/local/pubseq/bin/pfetch -F $acc |");
    while (<LOOK>) {
      print if ($verbose);
      
      if (/^\s/) {
	s/\s+//g;
	s/\d+//g;
	print OUT_MRNA "$_\n";
	print OUT_ACE  "$_\n" if ($ace);
      }
      # grab various details out of EMBL entry
      if (/^ID\s+(\S+)/)                         {$id  = $1;}
      if (/^SV\s+\S+\.(\d+)/)                    {$sv  = $1;}
      if (/^DE\s+(.+)/)                          {$def = $def." ".$1;}
      if (/^FT\s+\/protein_id=\"(\S+)\.(\d+)\"/) {$protid=$1; $protver=$2;}
      if (/^SQ/) {
	print OUT_MRNA ">$acc $id $def\n";
	if ($ace){
	  print OUT_ACE   "\nSequence : \"$acc\"\nDatabase EMBL $id $acc $sv\n";
	  print OUT_ACE   "Protein_id $acc $protid $protver\n";
	  print OUT_ACE   "Species \"Caenorhabditis elegans\"\n";
	  print OUT_ACE   "Title \"$def\"\nMethod NDB\n";
	  print OUT_ACE   "\nDNA \"$acc\"\n";
	}
	# reset vars
	$def = ""; $id = ""; $acc = ""; $sv = ""; $protid = ""; $protver ="";
      }
    }
  }
  # close filehandles
  close (SEQUENCES);  
  close(OUT_MRNA);
  close(OUT_ACE) if ($ace);


  
  # make blast database?
  if($blastdb){
    print LOG "Making blast database\n";
    system ("/usr/local/pubseq/bin/pressdb $dir/elegans_mRNAs > /dev/null");
  }
  
  # push to ftp site?
  if($ftp){
    print LOG "Copying to FTP site\n";
    system ("/bin/rm -f $ftpdir/elegans_mRNAs.gz");
    system ("cp $dir/elegans_ESTs $ftpdir/elegans_mRNAs");
    system ("/bin/gzip $ftpdir/elegans_mRNAs");
  }

}



#################################################################
#
# Other nematode species ESTs
#
#################################################################

sub make_nematode_ests{

  print LOG "Fetching other nematode EST sequences \n";

  # open filehandles for output files 
  open (OUT_NEM, ">$dir/other_nematode_ESTs");
  open (OUT_ACE, ">$dir/other_nematode_ESTs.ace") if ($ace);

  # Grab all EST sequences (division EST) which have taxon 'Nematoda' but not species C. elegans
  open (SEQUENCES, "$getz -e \'([embl-tax:Nematoda] & [embl-div:est] ! [embl-org:Caenorhabditis elegans])' |") ;
  while (<SEQUENCES>) {
    chomp;
    
    if (/^\s/) {
      s/\s+//g;
      s/\d+//g;
      print OUT_NEM "$_\n";
      print OUT_ACE "$_\n" if ($ace);
    }
    
    if (/^ID\s+(\S+)/)         {$id  = $1;}
    if (/^SV\s+(\S+)\.(\d+)/)  {$acc = $1; $sv = $2;}
    if (/^DE\s+(.+)/)          {$def = $def." ".$1;}
    if (/^OS\s+(.+)/)          {$org = $1;}
    if (/^SQ/) {
      print OUT_NEM ">$acc $id $def\n";
      if ($ace){
	print OUT_ACE "\nSequence : \"$acc\"\nDatabase EMBL $id $acc $sv\n";
	print OUT_ACE "Species \"$org\"\n";
	print OUT_ACE "Title \"$def\"\nMethod EST_nematode\n";
	print OUT_ACE "\nDNA \"$acc\"\n";
      }
      # reset vars
      $def = ""; $id = ""; $acc = ""; $sv = ""; $protid = ""; $protver ="";
    }
  }    
  
  # close filehandles
  close (SEQUENCES);      
  close(OUT_NEM);
  close(OUT_ACE) if ($ace);

  # pressdb fasta database
  if($blastdb){
    print LOG "Making blast database\n";
    system ("/usr/local/pubseq/bin/pressdb $dir/other_nematode_ESTs > /dev/null");
  }

  # push to ftp site?
  if($ftp){
    print LOG "Copying to FTP site\n";
    system ("/bin/rm -f $ftpdir/other_nematode_ESTs.gz");
    system ("cp $dir/elegans_ESTs $ftpdir/other_nematode_ESTs");
    system ("/bin/gzip $ftpdir/other_nematode_ESTs");
  }

}

#################################################################
#
# Non-wormbase C. elegans CDS in EMBL
#
#################################################################

sub make_embl_cds{

  print LOG "Fetching non-WormBase CDS containing EMBL accessions\n";

  open (OUT_EMBL, ">$dir/elegans_embl_cds");
  open (OUT_ACE, ">$dir/elegans_embl_cds.ace") if ($ace);
  
  # grab sequences in EST and ORG divisions which are genomic dna or unassigned DNA which are C. elegans but HTG sequences 
  #and which have CDS features
  open (SEQUENCES, "$getz -e \'(([embl-div:inv] & ([embl-mol:genomic dna] | [embl-mol:unassigned dna]) & [embl-org:Caenorhabditis elegans] ! [embl-Keywords:HTG]) & ([embl-FtKey:cds] > embl))\' |");


  while (<SEQUENCES>) {
    chomp;
    if (/^\s/) {                   # matches only the sequence lines
      s/\s+//g;                  # remove white space
      s/\d+//g;                  # remove numerals
      print OUT_ACE "$_\n" if ($ace);   # print to output
    }
    
    if (/^ID\s+(\S+)/)                         {$id  = $1;}
    if (/^SV\s+(\S+)\.(\d+)/)                  {$acc = $1; $sv  = $2;}
    if (/^DE\s+(.+)/)                          {$def = $def." ".$1;}
    if (/^FT\s+\/protein_id=\"(\S+)\.(\d+)\"/) {$protid=$1; $protver=$2;}
    if (/^SQ/) {
      print "// Parsed accession $acc\n" if ($verbose);
      
      open (CDS, "CDS.pl $acc |");   # Ugly. this needs rationalising dl
      while  (<CDS>) {
	print OUT_EMBL $_;
      }
      close(CDS);
      
      # print out the acefile version
      if ($ace){
	print OUT_ACE   "\nSequence : \"$acc\"\nDatabase EMBL $id $acc $sv\n";
	print OUT_ACE   "Species \"Caenorhabditis elegans\"\n";
	print OUT_ACE   "Title \"$def\"\nMethod NDB\n";
	print OUT_ACE  "\nDNA \"$acc\"\n";
      }
      # reset vars
      $def = ""; $id = ""; $acc = ""; $sv = ""; $protid = ""; $protver ="";
    }
  }
  
  close(SEQUENCES);
  close(OUT_EMBL);
  close(OUT_ACE) if ($ace);

  # pressdb fasta database
  if($blastdb){
    print LOG "Creating blast database\n";
    system ("/usr/local/pubseq/bin/pressdb $dir/elegans_embl_cds > /dev/null");
  }

  # push to ftp site?
  if($ftp){
    print LOG "Copying to FTP site\n";
    system ("/bin/rm -f $ftpdir/elegans_embl_cds.gz");
    system ("cp $dir/elegans_ESTs $ftpdir/elegans_embl_cds");
    system ("/bin/gzip $ftpdir/elegans_embl_cds");
  }
} 




#######################################################################
# Help and error trap outputs                                         #
#######################################################################

sub usage {
  my $error = shift;
  if ($error == 0) {
    # Normal help menu
    exec ('perldoc',$0);
  }
}
###############################################################################



sub create_log_files{

  # Create history logfile for script activity analysis
  $0 =~ m/\/*([^\/]+)$/; system ("touch /wormsrv2/logs/history/$1.`date +%y%m%d`");

  # create main log file using script name for
  my $script_name = $1;
  $script_name =~ s/\.pl//; # don't really need to keep perl extension in log name
  my $rundate     = `date +%y%m%d`; chomp $rundate;
  $log        = "/wormsrv2/logs/$script_name.$rundate.$$";

  open (LOG, ">$log") or die "cant open $log";
  print LOG "$script_name\n";
  print LOG "started at ",&runtime,"\n";
  print LOG "=============================================\n";
  print LOG "\n";

}

##########################################




__END__

=pod

=head2   NAME - fetch_EMBL_seqs_for_blatting.pl

=head1 USAGE

=over 4

=item fetch_EMBL_seqs_for_blatting.pl -[options]

=back

=head1 DESCRIPTION

This script runs various getzc commands (depending on options) to
fetch various sets of FASTA sequences (mainly for use by blat). The
script can also make ace file for these sequences, blast databases,
and/or copy the sequences to the FTP site for St. Louis.  All files
are initially generated in /nfs/disk100/wormpub/analysis/ESTs.

This script will be run on a cronjob and will run twice weekly.


=back

=head1 MANDATORY arguments: -est, -ost, -mrna, -embl, or -nematode

=over 4

=item -est

Returns all C. elegans sequences from the EST division of EMBL. 


=item -ost

This returns a subset of sequences from that specified by -ost. Namely those
sequences from Marc Vidal's Orfeome project 1.1.

=item -mrna

This returns all C. elegans sequences with an EMBL molecule identifier of
'*rna'.  This includes 'mRNA', 'pre-mRNA', and things like 'unclassified RNA' 
and 'other RNA'.  The getz query also discounts anything in EST division.

=item -embl

This returns non-WormBase CDS containing entries.  It does this by querying
the INV division of EMBL for C. elegans sequences which are either 'genomic DNA'
or 'unassigned DNA' but which don't have the 'HTG' keyword (this is what discounts
WormBase CDS's) but which also have a CDS tag.

=back

=head1 OPTIONAL arguments: -ace, -ftp, -blastdb, -help

=over 4

=item -ace

This option will make an acefile dump in addition to the fasta file dump.  This
is done for C. elegans ESTs and mRNAs and sometimes loaded back into camace by 
merge_split_camaces.pl

=item -ftp

If specified it will copy the fasta sequence file to the FTP site where St. Louis
can pick it up if they so wish (helps them stay in sync. with us).

=item -blastdb

Will make a blast database in the directory where sequences were downloaded.  Occasionally
used by WormBase people but not essential.

=item -debug <user>

Send log report to specified user only

=item -help

This help.

=back


=head1 AUTHOR Keith Bradnam (krb@sanger.ac.uk) 

but based on precursor scripts by Dan Lawson (dl1@sanger.ac.uk)

=back

=cut







