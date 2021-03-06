#!/usr/local/bin/perl5.8.0 -w

# Author: Chao-Kung Chen
# Last updated by $Author: mt3 $
# Last updated on: $Date: 2005-12-09 13:36:19 $ 

use strict;
use lib -e "/wormsrv2/scripts" ? "/wormsrv2/scripts" : $ENV{'CVS_DIR'}; 
use Wormbase;
use Ace;
use lib "/nfs/team71/worm/ck1/WORMBASE_CVS/scripts/";
use GENEACE::Geneace;


my $tace = &tace;

# grep email add. of PI in Laboratory class
my $db = Ace->connect(-path  => "/nfs/disk100/wormpub/DATABASES/geneace",
		      -program =>$tace) || print Ace->error;

my @labs = $db->fetch(-class => 'Laboratory',
		      -name  => '*');

my @emails;

foreach (@labs){
  if (defined $_ -> E_mail(1)){
    push(@emails, $_ -> E_mail(1) );
  }
}

#my $recipients = "krb\@sanger.ac.uk, ck1\@sanger.ac.uk";
my $recipients = "ck1\@sanger.ac.uk";
my $file = glob("~ck1/TMP/WB_wants_your_allele_data");

foreach (1..1){
  mail_maintainer("WormBase needs your allele data! - TEST", $recipients, $file);
}
