#!/usr/local/ensembl/bin/perl -w
#===============================================================================
#
#         FILE:  worm_lite.pl
#
#        USAGE:  ./worm_lite.pl
#
#  DESCRIPTION:
#
#       AUTHOR:   (Michael Han), <mh6@sanger.ac.uk>
#      COMPANY:
#      VERSION:  1.0
#      CREATED:  07/07/06 15:37:31 BST
#     REVISION:  ---
#===============================================================================

#####################################################################
# needs some makefile love to pull together all GFFs and Fastas
####################################################################

use strict;
use YAML;
use Getopt::Long;
use Storable;

use Bio::Seq;
use Bio::SeqIO;
use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Utils::Exception qw(verbose warning);
verbose('OFF');
use FindBin;
use lib "$FindBin::Bin/../lib";
use WormBase;
use DBI qw(:sql_types);

my ( $debug, $species, $setup, $dna, $genes, $test,$store, $yfile, $agp );

GetOptions(
  'species=s'  => \$species,
  'setup'      => \$setup,
  'load_dna'   => \$dna,
  'load_genes' => \$genes,
  'debug'      => \$debug,
  'test'       => \$test,
  'yfile=s'    => \$yfile,

) || die("bad commandline parameter\n");


die "You must supply a valid YAML config file\n" if not defined $yfile or not -e $yfile;

my $global_config = YAML::LoadFile($yfile);
my $config = $global_config->{$species};
if ($test) {
  $config = $global_config->{"${species}_test"};
}
my $cvsDIR = $test
  ? $global_config->{test}->{cvsdir}
  : $global_config->{generics}->{cvsdir};


my ($prod_db_host, $prod_db_port, $prod_db_name) = 
    ($global_config->{generics}->{ensprod_host},
     $global_config->{generics}->{ensprod_port},
     $global_config->{generics}->{ensprod_dbname});

my ($tax_db_host, $tax_db_port, $tax_db_name) = 
    ($global_config->{generics}->{taxonomy_host},
     $global_config->{generics}->{taxonomy_port},
     $global_config->{generics}->{taxonomy_dbname});


$WormBase::Species = $species;
our $gff_types = ($config->{gff_types} || "curated coding_exon");


&setupdb($config) if $setup;
&load_assembly($config)   if $dna;
&load_genes($config) if $genes;


##################################
# create database from schema
#
# hardcoded paths:
#      /nfs/acari/wormpipe/ensembl/ensembl-pipeline/scripts/DataConversion/wormbase/attrib_type.sql
#      /nfs/acari/wormpipe/ensembl/ensembl-pipeline/scripts/load_taxonomy.pl
#
# taxondb: ia64f -taxondbport 3365 -taxondbname ncbi_taxonomy / ens-livemirror 
#  if the taxondb goes down bully Abel

sub setupdb {
  my ( $conf ) = @_;
  
  my $db = $conf->{database};

  print ">>creating new database $db->{dbname} on $db->{host}\n";

  my $mysql = "mysql -h $db->{host} -P $db->{port} -u $db->{user} --password=$db->{password}";
  
  eval {
    print "Recreating database from scratch...\n";
    system("$mysql -e \"DROP DATABASE IF EXISTS $db->{dbname};\"") && die;
    system("$mysql -e \"create database $db->{dbname};\"")         && die;

    print "loading table.sql from ensembl...\n";
    system("$mysql $db->{dbname} < " . $cvsDIR . "/ensembl/sql/table.sql" ) && die;

    print "loading table.sql from ensembl-pipeline...\n";
    system("$mysql $db->{dbname} < " . $cvsDIR . "/ensembl-pipeline/sql/table.sql" ) && die;
    
    print "Populating meta table...\n";
    foreach my $key (keys %$config) {
      if ($key =~ /^meta\.(\S+)/) {
        my $db_key = $1;
        my $val = $config->{$key};
        
        system("$mysql -e 'INSERT INTO meta (meta_key,meta_value) VALUES (\"$db_key\",\"$val\");' $db->{dbname}") && die;
      }
    }
    system("$mysql -e 'INSERT INTO meta (meta_key,meta_value) VALUES (\"genebuild.start_date\",NOW());' $db->{dbname}") && die;

    print "Loading taxonomy: ";
    my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_taxonomy.pl -name \"$config->{species}\" "
        . "-taxondbhost $tax_db_host " 
        . "-taxondbport $tax_db_port "
        . "-taxondbname $tax_db_name "
        . "-lcdbhost $db->{host} "
        . "-lcdbport $db->{port} "
        . "-lcdbname $db->{dbname} "
        . "-lcdbuser $db->{user} "
        . "-lcdbpass $db->{password}";
    print "$cmd\n";        
    system($cmd) and die "Could not load taxonomy\n";
    
    print "Loading production table:\n";
    $cmd = "perl $cvsDIR/ensembl/misc-scripts/production_database/scripts/populate_production_db_tables.pl "
        . "--host $db->{host} "
        . "--user $db->{user} "
        . "--pass $db->{password} "
        . "--port $db->{port} "
        . "--database $db->{dbname} "
        . "--mhost $prod_db_host "
        . "--mport $prod_db_port "
        . "--mdatabase $prod_db_name "
	. "--dropbaks "
	. "--dumppath $ENV{'PIPELINE'}/dumps/ ";
    print "$cmd\n";
    system($cmd) and die "Could not populate production tables\n";

  };
  $@ and die("Error while building the database.");
}

# load genome sequences
sub load_assembly {
  my ($config) = @_;
  
  my $db = $config->{database};
  
  my $seq_level_coord_sys = $config->{seqlevel};
  my $top_level_coord_sys = $config->{toplevel};
  my $coord_sys_ver = $config->{assembly_version};

  my $seq_level_rank = ($seq_level_coord_sys eq $top_level_coord_sys) ? 1 : 2;
  my $top_level_rank = 1;

  if ($config->{agp}) {
    foreach my $glb (split(/,/, $config->{agp})) {
      foreach my $agp (glob("$glb")) {
        my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_seq_region.pl "
            . "-dbhost $db->{host} "
            . "-dbuser $db->{user} "
            . "-dbpass $db->{password} "
            . "-dbname $db->{dbname} "
            . "-dbport $db->{port} "
            . "-coord_system_name $top_level_coord_sys "
            . "-coord_system_version $coord_sys_ver "
            . "-rank $top_level_rank "
            . "-default_version "
            . "-agp_file $agp";
        print "Running: $cmd\n";
        system($cmd) and die "Could not load seq_regions from agp file\n";
      }
    }
  }

  foreach my $glb (split(/,/, $config->{fasta})) {
    foreach my $fasta (glob("$glb")) {
      my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_seq_region.pl "
          . "-dbhost $db->{host} "
          . "-dbuser $db->{user} "
          . "-dbpass $db->{password} "
          . "-dbname $db->{dbname} "
          . "-dbport $db->{port} "
          . "-coord_system_name $seq_level_coord_sys "
          . "-coord_system_version $coord_sys_ver "
          . "-rank $seq_level_rank "
          . "-default_version -sequence_level "
          . "-fasta_file $fasta";
      print "Running: $cmd\n";
      system($cmd) and die "Could not load seq_regions fasta file\n";
    }
  }

  if ($config->{agp}) {
    foreach my $glb (split(/,/, $config->{agp})) {
      foreach my $agp (glob("$glb")) {
        my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/load_agp.pl "
            . "-dbhost $db->{host} "
            . "-dbuser $db->{user} "
            . "-dbpass $db->{password} "
            . "-dbname $db->{dbname} "
            . "-dbport $db->{port} "
            . "-assembled_name $top_level_coord_sys "
            . "-assembled_version $coord_sys_ver "
            . "-component_name $seq_level_coord_sys "
            . "-component_version $coord_sys_ver "
            . "-agp_file $agp";
        print "Running: $cmd\n";
        system($cmd) and die "Could not load the assembly table from agp file\n";
      }
    }
  }
  
  my $cmd = "perl $cvsDIR/ensembl-pipeline/scripts/set_toplevel.pl "
      . "-dbhost $db->{host} "
      . "-dbport $db->{port} "
      . "-dbuser $db->{user} "
      . "-dbpass $db->{password} "
      . "-dbname $db->{dbname}" ;
  print "Running: $cmd\n";
  system($cmd) and die "Could not set toplevel\n";
  
  if ($config->{mitochondrial}) {
    my @mito_seqs = split(/,/, $config->{mitochondrial});

    $cmd = "perl $FindBin::Bin/set_codon_table.pl "
        . "-dbhost $db->{host} "
        . "-dbport $db->{port} "
        . "-dbuser $db->{user} "
        . "-dbpass $db->{password} "
        . "-dbname $db->{dbname} "
        . "-codontable 5 "
        . "@mito_seqs";
    print "Running: $cmd\n";
    system($cmd) and die "Could not set the mitochrondrial table";
  }

  # Finally, for elegans and briggsae, append the chromosome prefices (yuk, but it has to 
  # done to make BLAST dumping etc work properly
  if ($species eq 'elegans' or $species eq 'briggsae') {
    my $prefix = ($species eq 'elegans') ? 'CHROMOSOME_' : 'chr';

    my $mysql = "mysql -h $db->{host} -P $db->{port} -u $db->{user} --password=$db->{password} -D $db->{dbname}";
    my $sql = "UPDATE seq_region, coord_system "
        . "SET seq_region.name = CONCAT(\"$prefix\", seq_region.name) "
        . "WHERE seq_region.coord_system_id = coord_system.coord_system_id "
        . "AND coord_system.name = \"chromosome\"";
    print "Running: $mysql -e '$sql'\n";
    system("$mysql -e '$sql'") and die "Could not add chromosome prefixes to chromosome names\n";
  }

}


sub load_genes {
  my ($config) = @_;

  my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
    -host   => $config->{database}->{host},
    -user   => $config->{database}->{user},
    -dbname => $config->{database}->{dbname},
    -pass   => $config->{database}->{password},
    -port   => $config->{database}->{port},
      );
  my $analysis = $db->get_AnalysisAdaptor()->fetch_by_logic_name('wormbase');
  if (not defined $analysis) {
    $analysis = Bio::EnsEMBL::Analysis->new(-logic_name => "wormbase", 
                                            -gff_source => "WormBase",
                                            -gff_feature => "gene",
                                            -module => "WormBase");
    $db->get_AnalysisAdaptor->store($analysis);
  }

  my (%slice_hash, @path_globs, @gff_files, $genes); 

  foreach my $slice (@{$db->get_SliceAdaptor->fetch_all('toplevel')}) {
    $slice_hash{$slice->seq_region_name} = $slice;
    if ($species eq 'elegans') {
      my $other_name;
      if ($slice->seq_region_name !~ /^CHROMOSOME/) {
        $other_name = "CHROMOSOME_" . $slice->seq_region_name; 
      } else {
        $other_name = $slice->seq_region_name;
        $other_name =~ s/^CHROMOSOME_//;
      }
      $slice_hash{$other_name} = $slice;
    } elsif ($species eq 'briggsae') {
      my $other_name;
      if ($slice->seq_region_name !~ /^chr/) {
        $other_name = "chr" . $slice->seq_region_name; 
      } else {
        $other_name = $slice->seq_region_name;
        $other_name =~ s/^chr//;
      }
      $slice_hash{$other_name} = $slice;
    }
  }
  
  @path_globs = split(/,/, $config->{gff});

  foreach my $fglob (@path_globs) {
    push @gff_files, glob($fglob);
  }
  
  open(my $gff_fh, "cat @gff_files |") or die "Could not create GFF stream\n";
  $genes = &parse_gff_fh( $gff_fh, \%slice_hash, $analysis);
  &write_genes( $genes, $db );
  
  $db->dbc->do('UPDATE gene SET biotype="protein_coding"');
  $db->dbc->do('INSERT INTO meta (meta_key,meta_value) VALUES ("genebuild.start_date",NOW())');
}

package WormBase;

# redefine subroutine to interpret data simply
# - only consider CDS of each gene
# - create distinct "gene" for each isoform
sub process_file {
    my ($fh) = @_;
    my ( %genes, $transcript, %five_prime, %three_prime, %parent_seqs );

  LOOP: while (<$fh>) {
        chomp;
        my $element = $_;
        
        next LOOP if /^\#/;

        my ( $chr, $status, $type, $start, $end, $score, $strand, $frame, $sequence, $gene ) = split;

        my $line = $status . " " . $type;
        next LOOP if $line ne $gff_types;

        $gene =~ s/\"//g if $gene;

        if (not exists $genes{$gene}) {
          $genes{$gene} = [];
          $parent_seqs{$gene} = $chr;
          $five_prime{$gene}{$gene} = [];
          $three_prime{$gene}{$gene} = [];
        }
        push( @{ $genes{$gene} }, $element );
    }
    print STDERR "Have " . keys(%genes) . " genes (CDS)\n";
    return \%genes, \%five_prime, \%three_prime, \%parent_seqs;
}

1;
