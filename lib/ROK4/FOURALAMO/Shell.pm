# Copyright © (2011) Institut national de l'information
#                    géographique et forestière 
# 
# Géoportail SAV <contact.geoservices@ign.fr>
# 
# This software is a computer program whose purpose is to publish geographic
# data using OGC WMS and WMTS protocol.
# 
# This software is governed by the CeCILL-C license under French law and
# abiding by the rules of distribution of free software.  You can  use, 
# modify and/ or redistribute the software under the terms of the CeCILL-C
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info". 
# 
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability. 
# 
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or 
# data to be ensured and,  more generally, to use and operate it in the 
# same conditions as regards security. 
# 
# The fact that you are presently reading this means that you have had
# 
# knowledge of the CeCILL-C license and that you accept its terms.

################################################################################

=begin nd
File: Shell.pm

Class: ROK4::FOURALAMO::Shell

(see libperlauto/FOURALAMO_Shell.png)

Configure and assemble commands used to generate vector pyramid's slabs.

Using:
    (start code)
    use ROK4::FOURALAMO::Shell;

    if (! ROK4::FOURALAMO::Shell::setGlobals($commonTempDir)) {
        ERROR ("Cannot initialize Shell commands for FOURALAMO");
        return FALSE;
    }

    my $scriptInit = ROK4::FOURALAMO::Shell::getScriptInitialization($pyramid);
    (end code)
=cut

################################################################################

package ROK4::FOURALAMO::Shell;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use File::Basename;
use File::Path;
use Data::Dumper;

use ROK4::FOURALAMO::Node;


################################################################################

use constant TRUE  => 1;
use constant FALSE => 0;


####################################################################################################
#                                     Group: GLOBAL VARIABLES                                      #
####################################################################################################

our $SCRIPTSDIR;
our $COMMONTEMPDIR;
our $PERSONNALTEMPDIR;
our $PARALLELIZATIONLEVEL;

=begin nd
Function: setGlobals

Define and create common working directories
=cut
sub setGlobals {
    my $params = shift;

    $PARALLELIZATIONLEVEL = $params->{parallelization};
    $PERSONNALTEMPDIR = File::Spec->rel2abs($params->{directories}->{local_tmp});
    $COMMONTEMPDIR = File::Spec->rel2abs($params->{directories}->{shared_tmp});
    $SCRIPTSDIR = File::Spec->rel2abs($params->{directories}->{scripts});

    # Common directory
    if (! -d $COMMONTEMPDIR) {
        DEBUG (sprintf "Create the common temporary directory '%s' !", $COMMONTEMPDIR);
        eval { mkpath([$COMMONTEMPDIR]); };
        if ($@) {
            ERROR(sprintf "Can not create the common temporary directory '%s' : %s !", $COMMONTEMPDIR, $@);
            return FALSE;
        }
    }
    
    return TRUE;
}

# Function: getScriptDirectory
sub getScriptDirectory {
    return $SCRIPTSDIR;
}

# Function: getPersonnalTempDirectory
sub getPersonnalTempDirectory {
    return $PERSONNALTEMPDIR;
}

####################################################################################################
#                                        Group: MAKE JSONS                                         #
####################################################################################################

my $MAKEJSON = <<'FUNCTION';

mkdir -p ${TMP_DIR}/jsons/
MakeJson () {
    local srcsrs=$1
    local bbox=$2
    local bbox_ext=$3
    local dburl=$4
    local sql=$5
    local output=$6

    if [[ "${work}" == "0" ]]; then
        return
    fi

    OGR_ENABLE_PARTIAL_REPROJECTION=1 ogr2ogr -s_srs $srcsrs -f "GeoJSON" ${OGR2OGR_OPTIONS} -clipsrc $bbox_ext -spat $bbox -sql "$sql" ${TMP_DIR}/jsons/${output}.json PG:"$dburl"
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi     
}
FUNCTION

####################################################################################################
#                                        Group: MAKE TILES                                         #
####################################################################################################

my $MAKETILES = <<'FUNCTION';

mkdir -p ${TMP_DIR}/pbfs/
MakeTiles () {
    local top_level=$1
    local bottom_level=$2
    local generalization_options=$3

    if [[ "${work}" == "0" ]]; then
        return
    fi

    rm -r ${TMP_DIR}/pbfs/*

    tippecanoe ${TIPPECANOE_OPTIONS} $generalization_options --base-zoom ${top_level} --full-detail 0 -Z ${top_level} -z ${bottom_level} -e ${TMP_DIR}/pbfs/  ${TMP_DIR}/jsons/*.json
    if [ $? != 0 ] ; then echo $0; fi

    rm ${TMP_DIR}/jsons/*.json
}
FUNCTION

####################################################################################################
#                                        Group: PBF TO CACHE                                       #
####################################################################################################

my $S3_STORAGE_FUNCTIONS = <<'FUNCTION';
PushSlab () {
    local level=$1
    local ulcol=$2
    local ulrow=$3
    local imgName=$4

    if [[ "${work}" = "0" ]]; then
        # On regarde si l'image à pousser est la dernière traitée lors d'une exécution précédente
        if [[ "${imgName}" == "${last_slab}" ]]; then
            echo "Last generated image slab found, now we work"
            work=1
        fi

        return
    fi
    
    pbf2cache ${PBF2CACHE_OPTIONS} -r ${TMP_DIR}/pbfs/${level} -ultile $ulcol $ulrow -bucket ${PYR_BUCKET} ${PYR_PREFIX}/$imgName
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    echo "0/$imgName" >> ${TMP_LIST_FILE}
}
FUNCTION

my $SWIFT_STORAGE_FUNCTIONS = <<'FUNCTION';
PushSlab () {
    local level=$1
    local ulcol=$2
    local ulrow=$3
    local imgName=$4

    if [[ "${work}" = "0" ]]; then
        # On regarde si l'image à pousser est la dernière traitée lors d'une exécution précédente
        if [[ "${imgName}" == "${last_slab}" ]]; then
            echo "Last generated image slab found, now we work"
            work=1
        fi

        return
    fi
    
    pbf2cache ${PBF2CACHE_OPTIONS} -r ${TMP_DIR}/pbfs/${level} -ultile $ulcol $ulrow -container ${PYR_CONTAINER} ${PYR_PREFIX}/$imgName
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    echo "0/$imgName" >> ${TMP_LIST_FILE}
}
FUNCTION

my $CEPH_STORAGE_FUNCTIONS = <<'P2CFUNCTION';

PushSlab () {
    local level=$1
    local ulcol=$2
    local ulrow=$3
    local imgName=$4

    if [[ "${work}" = "0" ]]; then
        # On regarde si l'image à pousser est la dernière traitée lors d'une exécution précédente
        if [[ "${imgName}" == "${last_slab}" ]]; then
            echo "Last generated image slab found, now we work"
            work=1
        fi

        return
    fi

    pbf2cache ${PBF2CACHE_OPTIONS} -r ${TMP_DIR}/pbfs/${level} -ultile $ulcol $ulrow -pool ${PYR_POOL} ${PYR_PREFIX}/$imgName
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    echo "0/$imgName" >> ${TMP_LIST_FILE}

    print_prog
}
P2CFUNCTION


my $FILE_STORAGE_FUNCTIONS = <<'P2CFUNCTION';

PushSlab () {
    local level=$1
    local ulcol=$2
    local ulrow=$3
    local imgName=$4

    if [[ "${work}" = "0" ]]; then
        # On regarde si l'image à pousser est la dernière traitée lors d'une exécution précédente
        if [[ "${imgName}" == "${last_slab}" ]]; then
            echo "Last generated image slab found, now we work"
            work=1
        fi

        return
    fi

    local dir=`dirname ${PYR_DIR}/$imgName`
    if [ ! -d $dir ] ; then mkdir -p $dir ; fi

    pbf2cache ${PBF2CACHE_OPTIONS} -r ${TMP_DIR}/pbfs/${level} -ultile $ulcol $ulrow ${PYR_DIR}/$imgName
    if [ $? != 0 ] ; then echo $0 : Erreur a la ligne $(( $LINENO - 1)) >&2 ; exit 1; fi
    echo "0/$imgName" >> ${TMP_LIST_FILE}

    print_prog
}
P2CFUNCTION

####################################################################################################
#                                     Group: Main function                                         #
####################################################################################################

my $MAIN_SCRIPT = <<'MAINSCRIPT';
#!/bin/bash

################### CODES DE RETOUR #############################
# 0 -> SUCCÈS
# 1 -> ÉCHEC

###################### PARAMÈTRES ###############################
frequency=60
if [[ ! -z $1 ]]; then
    frequency=$1
fi

#################################################################

scripts_directory="__scripts_directory__"
if [[ ! -d "$scripts_directory" ]]; then
    echo "ERREUR $scripts_directory n'existe pas"
    exit 1
fi

SPLITS=()
SPLITS_PIDS=()
SPLITS_END=()
SPLITS_EXITCODE=()
SPLITS_NAME=()
SPLITS_STATUS=()

for (( i = 1; i <= __jobs_number__; i++ )); do
    SPLITS+=("${scripts_directory}/SCRIPT_${i}.sh")
    SPLITS_NAME+=("SCRIPT_${i}.sh")
    SPLITS_END+=("0")
    SPLITS_EXITCODE+=("0")
    SPLITS_STATUS+=("En cours")
done

for s in "${SPLITS[@]}"; do
    (bash $s >$s.log 2>&1) &
    split_pid=$!
    SPLITS_PIDS+=("$split_pid")
done

echo "  INFO Attente de la fin des __jobs_number__ splits 4ALAMO"
first_time="1"
while [[ "0" = "0" ]]; do
    still_one="0"
    for (( i = 0; i < __jobs_number__; i++ )); do
        p=${SPLITS_PIDS[$i]}
        e=${SPLITS_END[$i]}
        n=${SPLITS_NAME[$i]}

        if [[ "$e" = "1" ]]; then
            continue
        fi

        if [[ $(ps -o s,pid,wchan | grep " $p " | grep -v grep) ]] ; then
            still_one="1"
            continue
        fi

        wait $p
        if [[ "$?" = "0" ]]; then
            SPLITS_EXITCODE[$i]="0"
            SPLITS_STATUS[$i]="Succès"
            echo "$n -> Succès"
        else
            SPLITS_EXITCODE[$i]=$?
            SPLITS_STATUS[$i]="Échec"
            echo "$n -> Échec"
        fi

        SPLITS_END[$i]="1"
    done

    if [[ "$still_one" = "0" ]]; then
        break
    fi

    sleep $frequency
done

for (( i = 0; i < __jobs_number__; i++ )); do
    c=${SPLITS_EXITCODE[$i]}
    if [[ "${c}" != "0" ]]; then
        echo "ERREUR Un split au moins a échoué"
        exit 1
    fi
done

echo "  INFO Lancement du finisher 4ALAMO"

bash ${scripts_directory}/SCRIPT_FINISHER.sh >${scripts_directory}/SCRIPT_FINISHER.sh.log 2>&1
if [[ $? != "0" ]]; then
    echo "ERREUR le finisher a échoué"
    exit 1
fi

exit 0

MAINSCRIPT

=begin nd
Function: getMainScript

Get the main script allowing to launch all generation scripts on a same machine.

Returns:
    A shell script
=cut
sub getMainScript {
    my $ret = $MAIN_SCRIPT;

    $ret =~ s/__jobs_number__/$PARALLELIZATIONLEVEL/g;
    $ret =~ s/__scripts_directory__/$SCRIPTSDIR/g;

    return $ret;
}

####################################################################################################
#                                   Group: Export function                                         #
####################################################################################################

my $WORKANDPROG = <<'WORKANDPROG';
progression=-1
progression_file="$0.prog"
lines_count=$(wc -l $0 | cut -d' ' -f1)
start_line=0

print_prog () {
    tmp=$(( (${BASH_LINENO[-2]} - $start_line) * 100 / (${lines_count} - $start_line) ))
    if [[ "$tmp" != "$progression" ]]; then
        progression=$tmp
        echo "$tmp" >$progression_file
    fi
}

work=1

# Test d'existence de la liste temporaire
if [[ -f "${TMP_LIST_FILE}" ]] ; then 
    # La liste existe, ce qui suggère que le script a déjà commencé à tourner
    # On prend la dernière ligne pour connaître la dernière dalle complètement traitée
    
    last_slab=$(tail -n 1 ${TMP_LIST_FILE} | sed "s#^0/##")
    echo "Script ${SCRIPT_ID} recall, work from slab ${last_slab}"
    work=0
fi

WORKANDPROG

=begin nd
Function: getScriptInitialization

Parameters (list):
    pyramid - <ROK4::Core::PyramidVector> - Pyramid to generate

Returns:
    Global variables and functions to print into script
=cut
sub getScriptInitialization {
    my $pyramid = shift;

    my $string = $WORKANDPROG;

    $string .= "COMMON_TMP_DIR=\"$COMMONTEMPDIR\"\n";
    $string .= "LIST_FILE=\"$COMMONTEMPDIR/content.list\"\n";
    $string .= sprintf "FINAL_LIST_PATH=\"%s\"\n", $pyramid->getListPath();

    $string .= sprintf "OGR2OGR_OPTIONS=\"-a_srs %s -t_srs %s\"\n", $pyramid->getTileMatrixSet()->getSRS(), $pyramid->getTileMatrixSet()->getSRS();

    $string .= sprintf "TIPPECANOE_OPTIONS=\"--no-progress-indicator --no-tile-compression -s %s\"\n", $pyramid->getTileMatrixSet()->getSRS();

    $string .= sprintf "PBF2CACHE_OPTIONS=\"-t %s %s\"\n", $pyramid->getTilesPerWidth(), $pyramid->getTilesPerHeight();

    if ($pyramid->getStorageType() eq "FILE") {
        $string .= sprintf "PYR_DIR=%s\n", $pyramid->getDataRoot();
        $string .= $FILE_STORAGE_FUNCTIONS;
        $string .= $ROK4::Core::Shell::FILE_STORE_LIST;
    }
    elsif ($pyramid->getStorageType() eq "CEPH") {
        $string .= sprintf "PYR_POOL=%s\n", $pyramid->getDataPool();
        $string .= sprintf "PYR_PREFIX=%s\n", $pyramid->getName();
        $string .= $CEPH_STORAGE_FUNCTIONS;
        $string .= $ROK4::Core::Shell::CEPH_STORE_LIST;
    }
    elsif ($pyramid->getStorageType() eq "S3") {
        $string .= sprintf "PYR_BUCKET=%s\n", $pyramid->getDataBucket();
        $string .= sprintf "PYR_PREFIX=%s\n", $pyramid->getName();
        $string .= "HOST=\$(echo \${ROK4_S3_URL} | sed 's!.*://!!' | sed 's!:[0-9]\+\$!!')\n";
        $string .= $S3_STORAGE_FUNCTIONS;
        $string .= $ROK4::Core::Shell::S3_STORE_LIST;
    }
    elsif ($pyramid->getStorageType() eq "SWIFT") {
        $string .= sprintf "PYR_CONTAINER=%s\n", $pyramid->getDataContainer();
        $string .= sprintf "PYR_PREFIX=%s\n", $pyramid->getName();
        $string .= "export ROK4_SWIFT_TOKEN_FILE=\${TMP_DIR}/auth_token.txt\n";
        if (ROK4::Core::ProxyStorage::isSwiftKeystoneAuthentication()) {
            $string .= $ROK4::Core::Shell::SWIFT_KEYSTONE_TOKEN_FUNCTION;
        }
        else {
            $string .= $ROK4::Core::Shell::SWIFT_NATIVE_TOKEN_FUNCTION;
        }
        $string .= $SWIFT_STORAGE_FUNCTIONS;
        $string .= $ROK4::Core::Shell::SWIFT_STORE_LIST;
    }

    $string .= $MAKETILES;
    $string .= $MAKEJSON;

    $string .= "start_line=\$LINENO\n";
    $string .= "\n";
    
    return $string;
}
  
1;
__END__
