#!/usr/bin/env perl
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
File: 4head.pl

Section: 4HEAD tool

Synopsis:
    (start code)
    4head.pl --pyr <PATH> --tmsdir <DIRECTORY> --reference-level <LEVEL ID> --top-level <LEVEL ID> --tmp <DIRECTORY> --scripts <DIRECTORY> --parallel <INTEGER>
    (end code) 
=cut

################################################################################

use warnings;
use strict;

use POSIX qw(locale_h);

# Module
use Log::Log4perl qw(:easy);
use Getopt::Long;
use Cwd;
use List::Util qw(min max);
use File::Spec;
use File::Path;

# My search module
use FindBin qw($Bin);
use lib "$Bin/../lib/perl5";

# My module
use ROK4::Core::PyramidRaster;
use ROK4::Core::Utils;
use ROK4::FOURHEAD::Node;
use ROK4::FOURHEAD::Shell;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################
# Version
my $VERSION = '@VERSION@';

=begin nd
Variable: options

Contains 4head call options :

    version - To obtain the command's version
    help - To obtain the command's help
    usage - To obtain the command's usage
    
    pyr - To precise the pyramid's descriptor file
    tmsdir - The directory with TMS
    tmp - The directory to use for temporary files
    reference-level - The level from which above levels are regenerated
    top-level - The level to which above levels are regenerated
    parallel - Parallelization level. Optionnal
    
=cut
my %options =
(
    "version"    => 0,
    "help"       => 0,
    "usage"      => 0,

    # Mandatory
    "pyr"  => undef,
    "tmsdir"  => undef,
    "tmp"  => undef,
    "reference-level"  => undef,
    "top-level"  => undef,

    "parallel"  => undef
);

####################################################################################################
#                                         Group: Functions                                         #
####################################################################################################

=begin nd
Function: main

Main method.

See Also:
    <init>, <doIt>
=cut
sub main {
    printf("4HEAD : version [%s]\n",$VERSION);

    print STDOUT "BEGIN\n";

    # initialization
    ALWAYS("> Initialization");
    if (! main::init()) {
        print STDERR "ERROR INITIALIZATION !\n";
        exit 1;
    }

    # execution
    ALWAYS("> Execution");
    if (! main::doIt()) {
        print STDERR "ERROR EXECUTION !\n";
        exit 5;
    }

    print STDOUT "END\n";
}

=begin nd
Function: init

Checks and stores options, initializes the default logger. Checks TMS directory and the pyramid's descriptor file.
=cut
sub init {

    # init Getopt
    local $ENV{POSIXLY_CORRECT} = 1;

    Getopt::Long::config qw(
        default
        no_autoabbrev
        no_getopt_compat
        require_order
        bundling
        no_ignorecase
        permute
    );

    # init Options
    GetOptions(
        "help|h" => sub {
            printf "4head.pl --pyr <FILE> --tmsdir <DIRECTORY> --reference-level <LEVEL ID> --top-level <LEVEL ID> --tmp <DIRECTORY>  --scripts <DIRECTORY> [--parallel <INTEGER>]\n" ;
            exit 0;
        },
        "version|v" => sub { exit 0; },
        "usage" => sub {
            printf "4head.pl --pyr <FILE> --tmsdir <DIRECTORY> --reference-level <LEVEL ID> --top-level <LEVEL ID> --tmp <DIRECTORY>  --scripts <DIRECTORY> [--parallel <INTEGER>]\n" ;
            exit 0;
        },
        
        "pyr=s" => \$options{pyr},
        "tmsdir=s" => \$options{tmsdir},
        "tmp=s" => \$options{tmp},
        "scripts=s" => \$options{scripts},
        "reference-level=s" => \$options{"reference-level"},
        "top-level=s" => \$options{"top-level"},
        "parallel=s" => \$options{"parallel"},
    ) or do {
        printf "Unappropriate usage\n";
        printf "4head.pl --pyr <FILE> --tmsdir <DIRECTORY> --reference-level <LEVEL ID> --top-level <LEVEL ID> --tmp <DIRECTORY>  --scripts <DIRECTORY> [--parallel <INTEGER>]\n";
        exit -1;
    };
    
    # logger by default at runtime
    Log::Log4perl->easy_init({
        level => "INFO",
        layout => '%5p : %m (%M) %n'
    });
    
    ############# TMSDIR

    if (! defined $options{tmsdir} || $options{tmsdir} eq "") {
        ERROR("Option 'tmsdir' not defined !");
        return FALSE;
    }

    if (! -d $options{tmsdir}) {
        ERROR(sprintf "TMS directory does not exist : %s", $options{tmsdir});
        return FALSE;
    }

    ############# TMP

    if (! defined $options{tmp} || $options{tmp} eq "") {
        ERROR("Option 'tmp' not defined !");
        return FALSE;
    }

    $options{tmp} = File::Spec->rel2abs($options{tmp});

    if (! -d $options{tmp}) {
        eval { mkpath([$options{tmp}]); };
        if ($@) {
            ERROR(sprintf "Can not create the temporary directory '%s' : %s !", $options{tmp}, $@);
            return FALSE;
        }
    }

    ############# SCRIPTS

    if (! defined $options{scripts} || $options{scripts} eq "") {
        ERROR("Option 'scripts' not defined !");
        return FALSE;
    }

    $options{scripts} = File::Spec->rel2abs($options{scripts});

    if (! -d $options{scripts}) {
        eval { mkpath([$options{scripts}]); };
        if ($@) {
            ERROR(sprintf "Can not create the scripts' directory '%s' : %s !", $options{scripts}, $@);
            return FALSE;
        }
    }

    ############# PYR

    if (! defined $options{pyr} || $options{pyr} eq "") {
        ERROR("Option 'pyr' not defined !");
        return FALSE;
    }

    my $pyrObj = ROK4::Core::PyramidRaster->new("DESCRIPTOR", $options{pyr});
    if (! defined $options{pyr}) {
        ERROR(sprintf "Cannot load raster pyramid from descriptor %s", $options{pyr});
        return FALSE;
    }
    $options{pyr} = $pyrObj;

    if (! $options{pyr}->getTileMatrixSet()->isQTree()) {
        ERROR("Only QTree TMS is handled by 4head");
        return FALSE;
    }

    ############# REFERENCE LEVEL

    if (! defined $options{"reference-level"} || $options{"reference-level"} eq "") {
        ERROR("Option 'reference-level' not defined !");
        return FALSE;
    }

    if (! defined $options{pyr}->getLevel($options{"reference-level"})) {
        ERROR("Provided reference level is not a level ID of the pyramid");
        return FALSE;
    }

    $options{"reference-level"} = $options{pyr}->getTileMatrixSet()->getTileMatrix($options{"reference-level"});

    ############# TOP LEVEL

    if (! defined $options{"top-level"} || $options{"top-level"} eq "") {
        ERROR("Option 'top-level' not defined !");
        return FALSE;
    }

    $options{"top-level"} = $options{pyr}->getTileMatrixSet()->getTileMatrix($options{"top-level"});

    if ($options{"top-level"}->getOrder() <= $options{"reference-level"}->getOrder()) {
        ERROR("Top level have to be strictly above the reference level");
        return FALSE;
    }


    ############# PARALLEL

    if (! defined $options{"parallel"} || $options{"parallel"} eq "") {
        $options{"parallel"} = 1;
    } else {
        if (! ROK4::Core::Utils::isPositiveInt($options{"parallel"})) {
            ERROR("Parallel option have to be a positive integer");
            return FALSE;
        }        
    }

    return TRUE;
}

####################################################################################################
#                                 Group: Process methods                                           #
####################################################################################################

=begin nd
Function: doIt

Use classes :
    - <ProxyStorage::remove>
=cut
sub doIt {

    if (! $options{pyr}->loadList()) {
        ERROR("Cannot cache content list of the pyramid");
        return FALSE;
    }

    my $tms = $options{pyr}->getTileMatrixSet();

    my $referenceOrder = $options{"reference-level"}->getOrder();
    my $referenceID = $options{"reference-level"}->getID();

    my $topOrder = $options{"top-level"}->getOrder();
    my $topID = $options{"top-level"}->getID();

    # On part des dalles présentes dans la pyramide au niveau de référence
    my $referenceLevelSlabs = $options{pyr}->getLevelSlabs($referenceID);
    if (! exists $referenceLevelSlabs->{DATA}) {
        WARN("No DATA slab in level $referenceID in the pyramid");
        return TRUE;
    }

    my @referenceNodes = ();

    # Liste des dalles du niveau de référence
    INFO("List reference level nodes");
    foreach my $key (keys(%{$referenceLevelSlabs->{DATA}})) {

        if ($options{pyr}->ownMasks() && ! exists $referenceLevelSlabs->{MASK}->{$key}) {
            ERROR("Pyramid have to own masks and a data slab have no associated mask according the list");
            return FALSE;
        }
        my ($COL, $ROW) = split(/_/, $key);

        push(
            @referenceNodes,
            ROK4::FOURHEAD::Node->new({
                col => $COL,
                row => $ROW,
                level => $referenceID
            })
        );
    }

    # Création des niveaux qui n'existeraient pas dans la pyramide à modifier
    INFO("Add new levels");
    for (my $levelOrder = $referenceOrder + 1; $levelOrder <= $topOrder; $levelOrder++) {
        my $levelID = $tms->getIDfromOrder($levelOrder);

        if (defined $options{pyr}->getLevel($levelID)) {next;}

        $options{pyr}->addLevel($levelID);
    }

    # Création de l'arbre des noeuds (dalles) à regénérer
    INFO("Identify nodes");
    my $regeneratedNodes = {};
    foreach my $referenceNode (@referenceNodes) {

        my $childNode = $referenceNode;

        for (my $levelOrder = $referenceOrder + 1; $levelOrder <= $topOrder; $levelOrder++) {
            my $levelID = $tms->getIDfromOrder($levelOrder);

            my $col = int($childNode->getCol() / 2);
            my $row = int($childNode->getRow() / 2);

            my $stop = FALSE;
            if (exists $regeneratedNodes->{$levelID}->{"${col}_$row"}) {
                $stop = TRUE;
            } else {
                $regeneratedNodes->{$levelID}->{"${col}_$row"} = ROK4::FOURHEAD::Node->new({
                    col => $col,
                    row => $row,
                    level => $levelID
                });
            }

            if (! $regeneratedNodes->{$levelID}->{"${col}_$row"}->addSourceNode($childNode)) {
                ERROR("Conflict building the tree");
                return FALSE;
            }

            if ($stop) {last;}

            $childNode = $regeneratedNodes->{$levelID}->{"${col}_$row"};
        }

    }

    if (! ROK4::FOURHEAD::Shell::setGlobals($options{parallel}, $options{tmp}, $options{scripts})) {
        ERROR ("Impossible d'initialiser la librairie des commandes Shell pour FOURHEAD");
        return FALSE;
    }

    # Ouverture des flux d'écriture vers les scripts (le finisher est placé à la fin)
    INFO("Open scripts");
    my $scriptInit = ROK4::FOURHEAD::Shell::getScriptInitialization($options{pyr});
    my @scripts = ();
    my $splitIndex = 0;

    for (my $i = 1; $i <= $options{parallel}; $i++) {
        my $scriptPath = File::Spec->catfile($options{scripts}, "SCRIPT_${i}.sh");
        my $STREAM;
        open($STREAM, ">$scriptPath") or do {
            ERROR("Cannot open '$scriptPath' to write in it");
            return FALSE;
        };
        print $STREAM "$scriptInit\n";
        push(@scripts, $STREAM);
    }

    my $scriptPath = File::Spec->catfile($options{scripts}, "SCRIPT_FINISHER.sh");
    my $STREAM;
    open($STREAM, ">$scriptPath") or do {
        ERROR("Cannot open '$scriptPath' to write in it");
        return FALSE;
    };
    print $STREAM "$scriptInit\n";
    push(@scripts, $STREAM);

    # Recherche du niveau le plus haut qui contient au moins cinq fois plus de noeuds qu'il n'y a de scripts (en partant du bas)
    my $cutId = undef;
    my $cutOrder = undef;
    for (my $levelOrder = $referenceOrder + 1; $levelOrder <= $topOrder; $levelOrder++) {
        my $levelID = $tms->getIDfromOrder($levelOrder);
        if (! defined $cutOrder) {
            $cutOrder = $levelOrder;
            $cutId = $levelID;
            next;
        }

        if (scalar(keys(%{$regeneratedNodes->{$levelID}})) < 5 * $options{parallel}) {
            last;
        }

        $cutOrder = $levelOrder;
        $cutId = $levelID;
    }

    INFO("Cut level = $cutId");

    # Traitement des noeuds du niveau de coupure (et d'en dessous par récurrence)
    INFO("Process nodes below the cut level");
    foreach my $nodeIndice (keys(%{$regeneratedNodes->{$cutId}})) {
        my $node = $regeneratedNodes->{$cutId}->{$nodeIndice};
        $node->treatBelowCut($options{pyr}, $scripts[$splitIndex]);
        # Round robin
        $splitIndex = ($splitIndex + 1) % $options{parallel};
    }

    # Traitement des noeuds au dessus du niveau de coupure
    INFO("Process nodes above the cut level");
    foreach my $nodeIndice (keys(%{$regeneratedNodes->{$topID}})) {
        my $node = $regeneratedNodes->{$topID}->{$nodeIndice};
        $node->treatAboveCut($options{pyr}, $scripts[-1], $cutId);
    }

    # Fermeture des flux vers les scripts
    INFO("Close scripts");
    foreach my $STREAM (@scripts) {
        close($STREAM);
    }

    # Écrire le nouveau descripteur
    INFO("Flush descriptor");
    if (! $options{pyr}->writeDescriptor()) {
        ERROR("Cannot overwrite the pyramid descriptor");
        return FALSE;
    }

    # Écrire la nouvelle liste
    INFO("Flush list");
    if (! $options{pyr}->flushCachedList()) {
        ERROR("Cannot overwrite the pyramid list");
        return FALSE;
    }

    # Écrire le script principal
    INFO("Write main script");
    $scriptPath = File::Spec->catfile($options{scripts}, "main.sh");
    open(MAIN, ">$scriptPath") or do {
        ERROR("Cannot open '$scriptPath' to write in it");
        return FALSE;
    };

    print MAIN ROK4::FOURHEAD::Shell::getMainScript();

    close(MAIN);

    INFO("To run all scripts on the same machine, run :");
    INFO("\t bash $scriptPath");

    return TRUE;
}

################################################################################

BEGIN {}
INIT {}

main;
exit 0;

END {}

################################################################################

1;
__END__

=begin nd
Section: Details

Group: Command's options

    --help - Display the link to the technic documentation.

    --usage - Display the link to the technic documentation.

    --version - Display the tool version.
=cut
