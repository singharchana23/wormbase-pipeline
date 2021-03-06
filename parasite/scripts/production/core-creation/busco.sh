# Run busco

set -e

if [ ! -f "$1" ] ; then echo "Usage: $0 species/species.fa [roundworm/flatworm]" ; exit 1 ; fi 
 
module load busco
if [ ! -d "$BUSCO" ] ; then echo "Importing BUSCO didn't work!" ; exit 1 ; fi

fasta=$1
species=$(basename $(dirname $fasta) )

phylum=${2}
core_db=$($PARASITE_STAGING_MYSQL -e 'show databases' | grep "${species}_core_${PARASITE_VERSION}_${ENSEMBL_VERSION}" | head -n 1)

if [ "$phylum" == roundworm ] || [ 1 -eq "$($PARASITE_STAGING_MYSQL --column-names=FALSE $core_db -e 'select count(*) from meta where meta_value="Nematoda";' )" ] ; then
  species_parameter_for_augustus=caenorhabditis
  busco_library=$BUSCO/nematoda_odb9
elif [ "$phylum" == flatworm ] || [ 1 -eq "$($PARASITE_STAGING_MYSQL --column-names=FALSE $core_db -e 'select count(*) from meta where meta_value="Platyhelminthes";')" ] ; then
  species_parameter_for_augustus=schistosoma
  busco_library=$BUSCO/metazoa_odb9
else
   >&2 echo "$species does not look like a nematode or a platyhelminth- which is bad because we don't know what Augustus parameters and BUSCOs to use"
   exit 1
fi

BUSCO_TMP=$PARASITE_SCRATCH/busco/WBPS${PARASITE_VERSION}/$species

mkdir -p $BUSCO_TMP

cd $BUSCO_TMP

run_log=$BUSCO_TMP/run-busco.$(date "+%Y-%m-%d").out
python3 $BUSCO/BUSCO.py -sp $species_parameter_for_augustus -l $busco_library -o $species -i $fasta -c 8 -m genome -f -r \
  | tee $run_log 

#BUSCO doesn't reliably use status codes
#https://gitlab.com/ezlab/busco/issues/84 
if grep '^CRITICAL\|^ERROR' $run_log ; then
  echo "Run log said a worrying thing. Bailing out!"
  exit 1
fi


result=$BUSCO_TMP/run_$species/short_summary_${species}.txt

if [ ! -f "$result" ] ; then >&2 echo "Could not find the result file $result - did BUSCO succeed? " ; exit 1 ; fi
if [ ! "$core_db" ] ; then  >&2 echo "No core db - go read $result. Finishing " ; exit; fi  

${PARASITE_STAGING_MYSQL}-ensrw $core_db -e 'delete from meta where meta_key like "assembly.busco%"'

echo "Parsing the result file: $result"

perl -ne 'print "assembly.busco_complete\t$1\nassembly.busco_duplicated\t$2\nassembly.busco_fragmented\t$3\nassembly.busco_missing\t$4\nassembly.busco_number\t$5\n" if /C:([0-9.]+).*D:([0-9.]+).*F:([0-9.]+).*M:([0-9.]+).*n:(\d+)/' $result \
  | while read meta_key meta_value ; do
  ${PARASITE_STAGING_MYSQL}-ensrw $core_db -e "insert into meta (meta_key, meta_value) values (\"$meta_key\", \"$meta_value\");"
done 

echo "Parsed the results and inserted into the meta table. DONE"
