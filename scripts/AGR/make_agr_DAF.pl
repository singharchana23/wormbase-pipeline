#!/usr/bin/env perl

use strict;
use Storable;	
use Getopt::Long;
use Ace;


use lib $ENV{CVS_DIR};
use Wormbase;
use Log_files;

use lib "$ENV{CVS_DIR}/ONTOLOGY";
use GAF;

my ($help, $debug, $test, $verbose, $store, $wormbase);
my ($outfile, $acedbpath, $include_iea, $outfh);

GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"    => \$store,
	    "database:s" => \$acedbpath,
	    "outfile:s"   => \$outfile,
            "electronic" => \$include_iea,
	    );

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
      );
}

my $tace = $wormbase->tace;
my $log  = Log_files->make_build_log($wormbase);
my $date = &get_GAF_date();
my $taxid = $wormbase->ncbi_tax_id;
my $full_name = $wormbase->full_name;

$acedbpath = $wormbase->autoace unless $acedbpath;

if ($outfile) {
  open($outfh, ">$outfile") or $log->log_and_die("cannot open $outfile : $!\n");  
} else {
  $outfh = \*STDOUT;
}


$log->write_to("Connecting to database $acedbpath\n");
my $db = Ace->connect(-path => $acedbpath,  -program => $tace) or $log->log_and_die("Connection failure: ". Ace->error);

my ( $count, $it);


&print_DAF_header($outfh);

$it = $db->fetch_many(-query=>'find Gene Disease_info');

while (my $obj=$it->next) {
  next unless $obj->isObject();
  next unless $obj->Species;
  next unless $obj->Species->name eq $full_name;

  my $g = $obj->name;

  if ($include_iea) {
    foreach my $doterm ($obj->Potential_model) {
      
      my $meth = $doterm->right->right;
      if ($meth->name eq 'Inferred_automatically') {
        my $text = $meth->right->name;
        my ($with_from_list) = $text =~ /\((\S+)\)/;
        
        my @ens = map { "ENSEMBL:$_" } grep { $_ =~ /ENSG\d+/ } split(/,/, $with_from_list);
        my @omim = grep { $_ =~ /OMIM:/ } split(/,/, $with_from_list);
        
        my $obj =  {
          object_type => "gene",
          object_id => $g,
          object_symbol =>  $obj->Public_name->name,
          do_id => $doterm,
          reference => "PMID:19029536",  # this is the reference for Ensembl Compara
          evidence => "IEA", 
          with => join("|", @ens,@omim),
        };
        
        &print_DAF_line($outfh, $obj);
      }
    }
  }

  foreach my $doterm ($obj->Experimental_model) {
    my (@papers);
    foreach my $evi ($doterm->right->col) {
      if ($evi->name eq 'Paper_evidence') {
        foreach my $paper ($evi->col) {
          my $pmid;
          foreach my $db ($paper->Database) {
            if ($db->name eq 'MEDLINE') {
              $pmid = $db->right->right->name;
              last;
            }
          }
          push @papers, $pmid if $pmid;
        }
      } 
    }
    foreach my $paper (@papers) {
      my $obj = {
        object_type => "gene",
        object_id => $g,
        object_symbol =>  $obj->Public_name,
        do_id => $doterm,
        evidence => "IMP", 
        reference => "PMID:$paper", 
        assoc_type => 'causes_condition',
        sex => "hermaphrodite",
      };
      &print_DAF_line($outfh, $obj);  
    }
  }
}

$db->close;
$log->mail;

exit(0);

	
###########################################################3
sub print_DAF_header {
  my ($fh) = @_;

  print $fh "!daf-version 0.1\n";
  print $fh "!Project_name: WormBase\n";

}

###########################################################3
sub print_DAF_line {
  my ($fh, $obj) = @_;

  printf($fh "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", 
         $taxid,
         $obj->{object_type}, 
         "WB", 
         $obj->{object_id},
         $obj->{object_symbol},
         (exists $obj->{inferred_ga}) ? $obj->{inferred_ga} : "",
         (exists $obj->{product_id}) ? $obj->{product_id} : "",
         $obj->{assoc_type},
         (exists $obj->{qualifier}) ? $obj->{qualifier} : "",
         $obj->{do_id},
         (exists $obj->{with}) ? $obj->{with} : "",
         (exists $obj->{mod_assoc_type}) ? $obj->{mod_assoc_type} : "",
         (exists $obj->{mod_assoc_type}) ? $obj->{mod_assoc_type} : "",
         (exists $obj->{mod_qualifier}) ? $obj->{mod_qualifier} : "",
         (exists $obj->{mod_genetic}) ? $obj->{mod_genetic} : "",
         (exists $obj->{mod_exp_cond}) ? $obj->{mod_exp_cond} : "",
         $obj->{evidence},
         $obj->{sex},
         $obj->{reference},
         $date,
         "WB");

}
