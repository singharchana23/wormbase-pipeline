#!/nfs/disk100/wormpub/bin/perl
#
# wormBLAST.pl
#
# written by Anthony Rogers
#
# Last edited by: $Author: mh6 $
# Last edited on: $Date: 2008-04-11 09:13:49 $
#
# it depends on:
#    wormpep + history
#    database_used_in_build
#    ENSEMBL/worm_lite.pl
#    ENSEMBL/lib/WormBase.pm
#    ENSEMBL/etc/ensembl_lite.yml
#    /software/worm/ensembl/ensembl-conf/<species>

use lib '/software/worm/ensembl/ensembl/modules';
use lib '/software/worm/ensembl/ensembl-pipeline/modules';
use lib '/software/worm/lib/bioperl-live';

use Bio::EnsEMBL::DBSQL::DBConnection;
use strict;

use FindBin qw($Bin);
use lib "$Bin";
use lib "$Bin/BLAST_scripts";
use lib "$Bin/ENSEMBL/lib";

use WormBase;
use Wormbase;
use Getopt::Long;
use File::Path;
use File::Copy;
use Storable;
use YAML;

#######################################
# command-line options                #
#######################################

my ( $species, $update_mySQL, $clean_blasts, $update_analysis );
my ( $run_pipeline, $run_brig, $dump_data, $copy, $WS_version );
my ( $prep_dump, $cleanup, $test_pipeline );

my ( $debug, $test, $store, $wormbase, $log, $WP_version );
my $errors = 0;    # for tracking global error - needs to be initialised to 0

GetOptions(
    "updatemysql"     => \$update_mySQL,
    'update_analysis' => \$update_analysis,
    "run"             => \$run_pipeline,
    "prep_dump"       => \$prep_dump,
    "dump"            => \$dump_data,         # does that work ??? I wuold guess not
    "testpipe"        => \$test_pipeline,
    "version=s"       => \$WS_version,
    "cleanup"         => \$cleanup,
    "debug=s"         => \$debug,
    "test"            => \$test,
    "store:s"         => \$store,
    'species=s'       => \$species,
    'clean_blasts'    => \$clean_blasts,
    'copy'            => \$copy,
  )
  || die('cant parse the command line parameter');

my $wormpipe_dir = '/lustre/work1/ensembl/wormpipe';
my $scripts_dir  = $ENV{'CVS_DIR'};

# defaults
my $organism = ( $species || 'Elegans' );

if ($store) {
    $wormbase = retrieve($store)
      or croak("Can't restore wormbase from $store\n");
}
else {
    $wormbase = Wormbase->new(
        -debug    => $debug,
        -test     => $test,
        -version  => $WS_version,
        -organism => $organism,
    );
}

# establish log file. Can't do this if the BUILD/autoace directory has been moved to DATABASES
$log = Log_files->make_build_log($wormbase) unless $cleanup;

$WS_version ||= $wormbase->get_wormbase_version;
my $WS_old = $WS_version - 1;

my $last_build_DBs  = "$wormpipe_dir/BlastDB/databases_used_WS$WS_old";
my $database_to_use = "$wormpipe_dir/BlastDB/databases_used_WS$WS_version";

$species ||= ref $wormbase;
$species =~ tr/[A-Z]/[a-z]/;

# worm_ensembl configuration part
my $species_ = ref($wormbase);
$species =~ s/^[A-Z]/[a-z]/;
my $yfile  = glob("~wormpub/wormbase/scripts/ENSEMBL/etc/ensembl_lite.conf");
my $config = ( YAML::LoadFile($yfile) )->{$species};
our $gff_types = ( $config->{gff_types} || "curated coding_exon" );

# mysql database parameters
my $dba = Bio::EnsEMBL::DBSQL::DBConnection->new(
    -user   => $config->{database}->{user},
    -dbname => $config->{database}->{dbname},
    -host   => $config->{database}->{host},
    -driver => 'mysql'
  )
  || die "cannot connect to db, $DBI::errstr";
$dba->password( $config->{database}->{password} );    # hate that (_&^$  , why can't it go into the constructor?

# get a clean handle to the database to use later
my $raw_dbh = $dba->db_handle;

# build blast logic_name->analysis_id hashes.
# one for blastx and one for blastp

my %worm_dna_processIDs = %{ get_logic2analysis( $raw_dbh, '%blastx' ) };
my %wormprotprocessIDs  = %{ get_logic2analysis( $raw_dbh, '%blastp' ) };

####################### copy files around ######################
# for chromosome , brigpep , wormpep , remapep
#

if ($copy) {
    foreach my $option (qw(wormpep remapep brigpep chrom)) { copy2acari($option) }    # don't need the chromosomes
}

########### updating databases ###############
my ( $updated_dbs, $current_dbs ) = &update_blast_dbs() if ($copy);

my @updated_DBs;# = @{$updated_dbs};
my %currentDBs;#  = %{$current_dbs};

&update_analysis if $update_analysis;

# update mySQL database
if ($update_mySQL) {
    my $dna_update = &update_dna();    # replace dna sequences based on md5?
    &update_analysis();                # done
    &update_proteins() unless $dna_update;    # axe transcripts based on translations
    print "\nFinished setting up MySQL databases\n\n";
}

###################### run blasts  -blastx -blastp ################################
# run_rule_manager if run_pipeline

if ($run_pipeline) {

}

################ cleanup dodgy blast hits -clean_blasts ##################
&clean_blasts( $raw_dbh, \%worm_dna_processIDs, \%wormprotprocessIDs ) if $clean_blasts;

################## -prep_dump #####################################
if ($prep_dump) {

    # prepare helper files gff2cds and gff2cos
    my $autoace = $wormbase->autoace;
    my $wormpep = $wormbase->wormpep;
    if ( -e $wormbase->gff_splits . "/CHROMOSOME_X_curated.gff" ) {
        $wormbase->run_command(
            "cat "
              . $wormbase->gff_splits
              . "/CHROMOSOME_*_curated.gff | $scripts_dir/BLAST_scripts/gff2cds.pl "
              . "> $wormpipe_dir/Elegans/cds$WS_version.gff",
            $log
        );
        $wormbase->run_command(
            "cat "
              . $wormbase->gff_splits
              . "/CHROMOSOME_*_Genomic_canonical.gff | $scripts_dir/BLAST_scripts/gff2cos.pl "
              . "> $wormpipe_dir/Elegans/cos$WS_version.gff",
            $log
        );
        system("touch $wormpipe_dir/DUMP_PREP_RUN");
    }
    else { die( " cant find GFF files at " . $wormbase->gff_splits . "\n " ) }
}

##################### -cleanup ##################################
if ($cleanup) {
    print "clearing up files generated in this build\n";

    # files to move to ~wormpub/last-build/
    #   /lustre/work1/ensembl/wormpipe/dumps/
    #    ipi_hits_list
    #    trembllist.txt
    #    swisslist.txt
    #    best_blastp_hits
    #    best_blastp_hits_brigprot

    #  ~wormpipe/Elegans
    #    WS99.agp
    #    cds99.gff
    #    cos99.gff
    #    ids.txt

    # to delete
    #   /lustre/work1/ensembl/wormpipe/dumps/
    #      *.ace
    #      *.log
    my $clear_dump = "/lustre/work1/ensembl/wormpipe/dumps";
    print "Removing . . . \n\t$clear_dump/*.ace\n";
    system("rm -f $clear_dump/*.ace $clear_dump/*.log") && warn "cant remove ace and log files from $clear_dump";
    print "Removing files currently in $wormpipe_dir/last_build/n";
    system(" rm -f $wormpipe_dir/last_build/*.gff $wormpipe_dir/last_build/*.agp");
    print "\nmoving the following to ~wormpipe/last_build . . \n\t$clear_dump/*.txt\n";
    system("mv -f $clear_dump/*.txt $wormpipe_dir/last_build/") && warn "cant move $clear_dump/*.txt\n";
    print "\t$clear_dump/ipi*\n";
    system("mv -f $clear_dump/ipi* $wormpipe_dir/last_build/") && warn "cant move $clear_dump/ipi*\n";
    print "\t$clear_dump/best_blastp\n";
    system("mv -f $clear_dump/best_blastp* $wormpipe_dir/last_build/") && warn "cant move $clear_dump/best_blast*\n";
    print "\t$wormpipe_dir/Elegans/*\n";
    system("mv -f $wormpipe_dir/Elegans/* $wormpipe_dir/last_build/") && warn "cant move $wormpipe_dir/Elegans/*\n";
    print "\nRemoving the $wormpipe_dir/DUMP_PREP_RUN lock file\n";
    system("rm -f $wormpipe_dir/DUMP_PREP_RUN") && warn "cant remove $wormpipe_dir/DUMP_PREP_RUN\n";

    print "\nRemoving farm output and error files from /lustre/scratch1/ensembl/wormpipe/*\n";
    my $scratch_dir = "/lustre/scratch1/ensembl/wormpipe";
    my @directories = qw( 0 1 2 3 4 5 6 7 8 9 );

    foreach my $directory (@directories) {
        rmtree( "$scratch_dir/$directory", 1, 1 );    # this will remove the directory as well
        mkdir("$scratch_dir/$directory");             # so remake it
        system("chgrp worm $scratch_dir/$directory"); # and make it writable by 'worm'
    }
    print "\n\nCLEAN UP COMPLETED\n\n";
}

&wait_for_pipeline_to_finish if $test_pipeline;       # debug stuff
$log->mail;

exit(0);

###############################################################################################
#
#
#                          T  H  E     S  U  B  R  O  U  T  I  N  E  S
#
#
#
################################################################################################

# copy files to the farm
sub copy2acari {
    my ($option) = shift;
    $wormbase->run_script( "BLAST_scripts/copy_files_to_acari.pl -$option", $log );
}

# get logic_name -> analysis_id from the mysql database
sub get_logic2analysis {
    my ( $dbh_, $prog ) = @_;
    my $sth = $dbh_->prepare('SELECT logic_name,analysis_id FROM analysis WHERE program like ?')
      || die "cannot prepare statement, $DBI::errstr";
    $sth->execute($prog) || die "cannot execute statement, $DBI::errstr";
    my $blast = $sth->fetchall_arrayref() || die "cannot connect to db, $DBI::errstr";
    my %logic2analysis;
    map { $logic2analysis{ $_->[0] } = $_->[1] } @{$blast};
    return \%logic2analysis;
}

# clean blast hits
sub clean_blasts {
    my ( $dbh_, $dnaids, $pepids, $cutoff ) = @_;
    $cutoff ||= 0.001;
    while ( my ( $k, $v ) = each %$pepids ) {
        my $sth = $dbh_->do("delete FROM protein_feature WHERE evalue>=$cutoff AND analysis_id=$v")
          || die($DBI::errstr);
    }
    while ( my ( $k, $v ) = each %$dnaids ) {
        my $sth = $dbh_->do("delete FROM protein_align_feature WHERE evalue>$cutoff AND analysis_id=$v")
          || die($DBI::errstr);
    }
}

#############################
# parse the database files
#
sub get_updated_database_list {
    @updated_DBs = ();
    my @updated_dbfiles;

    # process new databases
    open( OLD_DB, "<$last_build_DBs" ) or die "cant find $last_build_DBs";
    my %prevDBs;

    # get database file info from databases_used_WS(xx-1) (should have been updated by script if databases changed
    while (<OLD_DB>) {
        chomp;
        if (/(ensembl|gadfly|yeast|slimswissprot|slimtrembl|wormpep|ipi_human|brigpep)/) {
            $prevDBs{$1} = $_;
        }
    }
    open( CURR_DB, "<$database_to_use" ) or die "cant find $database_to_use";
    while (<CURR_DB>) {
        chomp;
        if (/(ensembl|gadfly|yeast|slimswissprot|slimtrembl|wormpep|ipi_human|brigpep)/) {
            $currentDBs{$1} = $_;
        }
    }
    close CURR_DB;

    # compare old and new database list
    foreach ( keys %currentDBs ) {
        if ( "$currentDBs{$_}" ne "$prevDBs{$_}" ) {
            push( @updated_DBs,     "$_" );
            push( @updated_dbfiles, $currentDBs{$_} );
        }
    }
    return @updated_dbfiles;
}

##################################
# update and copy the blastdbs
# -distribute and -update_databases
sub update_blast_dbs {
    my %_currentDBs;    # ALSO used in setup_mySQL
    my @_updated_DBs;

    # used by get_updated_database_list sub - when run this array is filled with databases
    # that have been updated since the prev build
    # load in databases used in previous build

    open( OLD_DB, "<$last_build_DBs" ) or die "cant find $last_build_DBs";
    while (<OLD_DB>) {
        chomp;
        if (/(gadfly|yeast|slimswissprot|slimtrembl|wormpep|ipi_human|brigpep)/) {
            $_currentDBs{$1} = $_;
        }
    }
    close OLD_DB;

    # check for updated Databases
    print "Updating databases \n";
    open( DIR, "ls -l $wormpipe_dir/BlastDB/*.pep |" ) or die "readir\n";
    while (<DIR>) {
        chomp;
        if (/\/(gadfly|yeast|slimswissprot|slimtrembl|wormpep|ipi_human|brigpep)/) {
            my $whole_file = "$1" . "$'";    # match + stuff after match.

            if ( "$whole_file" ne "$_currentDBs{$1}" ) {

                # make blastable database
                print "\tmaking blastable database for $1\n";
                $wormbase->run_command( "/usr/local/ensembl/bin/xdformat -p $wormpipe_dir/BlastDB/$whole_file", $log );
                push( @_updated_DBs, $1 );

                #change hash entry ready to rewrite external_dbs
                $_currentDBs{$1} = "$whole_file";
            }
            else {
                print "\t$1 database unchanged $whole_file\n";
            }
        }
    }
    close DIR;

    open( NEW_DB, ">$database_to_use" ) or die "cant write updated $database_to_use";
    foreach ( keys %_currentDBs ) {
        print NEW_DB "$_currentDBs{$_}\n";
    }
    close NEW_DB;

    # copy the databases around
    my $blastdbdir = "/data/blastdb/Worms";
    &get_updated_database_list();

    # delete updated databases from /data/blastdb/Worms
    foreach (@_updated_DBs) {
        $log->write_to("deleting blastdbdir/$_*\n");
        ( unlink glob "$blastdbdir/$_*" )
          or $log->write_to("WARNING: cannot delete $blastdbdir/$_*\n");
    }
    $log->write_to("deleting $blastdbdir/CHROMOSOME_*.dna\n");
    ( unlink glob "$blastdbdir/CHROMOSOME_*.dna" )
      or $log->write_to("WARNING: cannot delete $blastdbdir/CHROMOSOME_*.dna\n");

    # copy blastdbs
    foreach (@_updated_DBs) {
        foreach my $file_name ( glob "$wormpipe_dir/BlastDB/$currentDBs{$_}*" ) {
            $log->write_to("copying $file_name to $blastdbdir/\n");
            copy( "$file_name", "$blastdbdir/" )
              or $log->write_to("ERROR: cannot copy $file_name\n");
        }
    }

    # copy chromosomes
    foreach my $chr ( $wormbase->get_chromosome_names( '-prefix' => 1, ) ) {
        my $file_name = "$wormpipe_dir/BlastDB/$chr.dna";
        $log->write_to("copying $file_name to $blastdbdir/");
        copy( $file_name, "$blastdbdir/" )
          or $log->write_to("cannot copy $file_name\n");
    }
    return ( \@_updated_DBs, \%_currentDBs );
}

###############################
# updating the dna sequences
#
# parse Gary's diff ?
# identify seq_region and axe any genes/transcripts/exons/translations/simple_features/protein_align_features/dna on it
# make input_ids for the new one
#
# or crude one: if different snowball a new database build
#
sub update_dna {
    my ($dbh) = @_;
    print "Updating mysql databases with new clone and protein info\n";

    # parse it and if different recreate the whole database, as we don't want to fiddle around with coordinates for the time being

    $log->write_to("Updating DNA sequences in mysql database\n-=-=-=-=-=-=-=-=-=-=-\n");

    # worm_lite.pl magic
    my $species = $wormbase->species;
    $wormbase->run_script( "ENSEMBL/scripts/worm_lite.pl -setup -load_dna -load_genes -species $species", $log );

    # create analys_tables and rules
    my $db_options = sprintf(
        "-dbhost %s -dbuser %s -dbpass %s -dbname %s -dbport %s",
        $config->{database}->{host},   $config->{database}->{user}, $config->{database}->{password},
        $config->{database}->{dbname}, $config->{database}->{port}
    );
    my $pipeline_scripts = '/software/worm/ensembl/ensembl-pipeline/scripts';
    my $conf_dir         = '/software/worm/ensembl/ensembl-config/generic';

    # * analysis_setup.pl -dbhost XYZ -dbuser XYZ - dbpass XYZ -dbname XYZ -dbport 3306 -read -file XYZ.conf
    $wormbase->run_command( "perl $pipeline_scripts/analysis_setup.pl $db_options -read -file $conf_dir/analysis.conf", $log );

    # * rule_setup.pl -dbhost XYZ -dbuser XYZ - dbpass XYZ -dbname XYZ -dbport 3306 -read -file XYZ.conf
    $wormbase->run_command( "perl $pipeline_scripts/rule_setup.pl $db_options -read -file $conf_dir/rule.conf", $log );

    # * make_input_ids -dbhost XYZ -dbname XYZ -dbuser XYZ -dbpass XYZ -dbport 3306 -translation_id -logic SubmitTranslation
    $wormbase->run_command( "perl $pipeline_scripts/make_input_ids $db_options -translation_id -logic SubmitTranslation", $log );

# * make_input_ids -dbhost XYZ -dbname XYZ -dbuser XYZ -dbpass XYZ -dbport 3306 -slice -slice_size 150000 -coord_system toplevel -logic_name SubmitSlice150k -input_id_type Slice150k
    $wormbase->run_command(
"perl $pipeline_scripts/make_input_ids $db_options -slice -slice_size 150000 -coord_system toplevel -logic_name SubmitSlice150k -input_id_type Slice150k",
        $log
    );
    return 1;
}

##############################
# update genes/proteins
#
#  heavily dependent on a working XYZpep.history file
#
sub update_proteins {
    my ($species_ref) = @_;

    # parse genes
    my @genes        = @{ parse_genes() };
    my $gene_adaptor = $dba->get_GeneAdaptor();

    # clean old genes
    my ( $new, $changed, $lost ) = parse_wormpep_history($wormbase);
    foreach my $gene ( @{$lost} )    { delete_gene_by_translation($gene) }
    foreach my $gene ( @{$changed} ) {
        delete_gene_by_translation($gene);
    }
    foreach my $gene (@genes) {

        # variant 2: update if it doesn't exist
        map { $gene_adaptor->save($gene) unless $dba->get_GeneAdaptor()->fetch_by_translation_stable_id( $_->translation->stable_id ) }
          @{ $gene->get_all_Transcripts };
    }

    # clean input_id_analysis table
    &clean_input_id();
}

# handy utility function
sub delete_gene_by_translation {
    $dba->get_GeneAdaptor()->fetch_by_translation_stable_id(shift)->remove;
}

# clean input_id_analysis table by dropping the translations and recreating them with the ensembl script
sub clean_input_id {
    $raw_dbh->do('DELETE FROM input_id_anlysis WHERE analysis_id = SELECT analysis_id FROM analysis WHERE logic_name="SubmitTranslation"');
    my $host     = $config->{database}->{host};
    my $dbname   = $config->{database}->{dbname};
    my $user     = $config->{database}->{user};
    my $pass     = $config->{database}->{password};
    my $cmd_line =
        'perl /software/worm/ensembl/ensembl-pipeline/scripts/make_input_ids'
      . " -dbhost $host -dbname $dbname -dbuser $user -dbpass $pass -dbport 3306 -translation_id -logic SubmitTranslation";
    $wormbase->run_command( $cmd_line, $log );
}

##############################
# create dummy genes from gff
#
sub parse_genes {

    my $analysis = $dba->get_AnalysisAdaptor()->fetch_by_logic_name('wormbase');

    my @genes;

    # elegans hack for build
    if ( ref($wormbase) eq 'Elegans' ) {
        foreach my $chr ( glob $config->{fasta} ) {
            my ( $path, $name ) = ( $chr =~ /(^.*)\/CHROMOSOMES\/(.*?)\.\w+/ );
            `mkdir /tmp/compara` if !-e '/tmp/compara';
            system("cat $path/GFF_SPLITS/${\$name}_gene.gff $path/GFF_SPLITS/${\$name}_curated.gff > /tmp/compara/${\$name}.gff")
              && die 'cannot concatenate GFFs';
        }
    }

    foreach my $file ( glob $config->{gff} ) {
        next if $file =~ /masked|CSHL|BLAT_BAC_END|briggsae|MtDNA/;
        $file =~ /.*\/(.*)\.gff/;
        print "parsing $1 from $file\n";
        my $slice = $dba->get_SliceAdaptor->fetch_by_region( 'chromosome', $1 );
        push @genes, @{ &parse_gff( $file, $slice, $analysis ) };
    }
    return \@genes;
}

# return @new , @changed , @lost cdses based on wormpep.diff
sub parse_wormpep_history {
    my ($wb) = @_;
    my $wp_file = glob( $wb->wormpep . '*.diff' );
    my @new;
    my @changed;
    my @lost;
    open INF, "<$wp_file";
    while (<INF>) {
        my @a = split;
        if ( $a[0] =~ /changed/ ) {
            push @changed, $a[1];
        }
        elsif ( $a[0] =~ /new/ ) {
            push @new, $a[1];
        }
        elsif ( $a[0] =~ /lost/ ) {
            push @lost, $a[1];
        }
    }
    close INF;
    return ( \@new, \@changed, \@lost );
}

#####################################
# update blasts based on the updated_dbs
#
sub update_analysis {
    my $update_dbfile_handle  = $raw_dbh->prepare('UPDATE analysis SET db_file = ? WHERE analysis_id = ?') || die "$DBI::errstr";
    my $clean_input_id_handle = $raw_dbh->prepare('DELETE FROM input_id_analysis WHERE analysis_id = ?')   || die "$DBI::errstr";
    my $analysis_for_file     = $raw_dbh->prepare('SELECT analysis_id FROM analysis WHERE db_file LIKE ?') || die "$DBI::errstr";

    print "Updating BLAST analysis ... \n";
    foreach my $db ( get_updated_database_list() ) {
        $db =~ /([a-z_]+)?[\d_]*\.pep/;
        $analysis_for_file->execute("/data/blastdb/Worms/$1%.pep") || die "$DBI::errstr";
        my $analysis = $analysis_for_file->fetchall_arrayref || die "$DBI::errstr";
        foreach my $ana (@$analysis) {
            print "updating analysis : ${\$ana->[0]} => /data/blastdb/Worms/$db\n";
            $update_dbfile_handle->execute( "/data/blastdb/Worms/$db", $ana->[0] ) || die "$DBI::errstr";
            $clean_input_id_handle->execute( $ana->[0] )                                        || die "$DBI::errstr";
            $raw_dbh->do("DELETE FROM protein_feature WHERE analysis_id = ${\$ana->[0]}")       || die "$DBI::errstr";
            $raw_dbh->do("DELETE FROM protein_align_feature WHERE analysis_id = ${\$ana->[0]}") || die "$DBI::errstr";
        }
    }

    # update the interpro analysis
    my $interpro_dir    = "/data/blastdb/Ensembl/interpro_scan/";
    my $interpro_date   = 1000;
    my $last_build_date = -M $last_build_DBs;
    if ( -e $interpro_dir ) {
        $interpro_date = -M $interpro_dir;
    }
    else {
        print "Can't find the InterPro database directory: $interpro_dir\n";
    }

    # see if the InterPro databases' directory has had stuff put in it since the last build
    if ( $interpro_date < $last_build_date ) {
        print "doing InterPro updates . . . \n";

        # delete entries so they get rerun
        $raw_dbh->do('DELETE FROM protein_feature WHERE analysis_id IN (select analysis_id FROM analysis WHERE module LIKE "ProteinAnnotation%"')
          || die "$DBI::errstr";
        $raw_dbh->do('DELETE FROM input_analysis_id WHERE analysis_id IN (select analysis_id FROM analysis WHERE module LIKE "ProteinAnnotation%")')
          || die "$DBI::errstr";
    }
}

package WormBase;

# redefine subroutine to use different tags
sub process_file {
    my ($fh) = @_;
    my ( %genes, $transcript, %five_prime, %three_prime );

    while (<$fh>) {
        chomp;

        my ( $chr, $status, $type, $start, $end, $score, $strand, $frame, $sequence, $gene ) = split;
        my $element = $_;

        next if ( /^#/ || $chr =~ /sequence-region/ || ( !$status && !$type ) );
        my $line = $status . " " . $type;
        $gene =~ s/\"//g if $gene;
        if ( ( $line eq 'Coding_transcript five_prime_UTR' ) or ( $line eq 'Coding_transcript three_prime_UTR' ) ) {
            $transcript = $gene;

            #remove transcript-specific part: Y105E8B.1a.2
            $gene =~ s/(\.\w+)\.\d+$/$1/ unless $species eq 'brugia';    # for that if i will go to hell :-(
            my $position = $type;
            if ( $position =~ /^five/ ) {
                $five_prime{$gene} = {} if ( !$five_prime{$gene} );
                $five_prime{$gene}{$transcript} = [] if ( !$five_prime{$gene}{$transcript} );
                push( @{ $five_prime{$gene}{$transcript} }, $element );
            }
            elsif ( $position =~ /^three/ ) {
                $three_prime{$gene} = {} if ( !$three_prime{$gene} );
                $three_prime{$gene}{$transcript} = [] if ( !$three_prime{$gene}{$transcript} );
                push( @{ $three_prime{$gene}{$transcript} }, $element );
            }
            next;
        }
        elsif ( $line ne $gff_types ) { next }    # <= here goes the change needs tp become $line eq "$bla $blub"
        $genes{$gene} ||= [];
        push( @{ $genes{$gene} }, $element );
    }
    print STDERR "Have " . keys(%genes) . " genes (CDS), " . keys(%five_prime) . " have 5' UTR and " . keys(%three_prime) . " have 3' UTR information
\n";
    return \%genes, \%five_prime, \%three_prime;
}
## Please see file perltidy.ERR
