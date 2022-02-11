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
File: joinCache-file.pl
=cut

################################################################################

use warnings;
use strict;

use POSIX qw(locale_h);

use Getopt::Long;

use Data::Dumper;
local $Data::Dumper::Maxdepth = 2;
use Math::BigFloat;
use File::Basename;
use File::Spec;
use File::Path;
use Cwd;

use Log::Log4perl qw(:easy);

# My search module
use FindBin qw($Bin);
use lib "$Bin/../lib/perl5";

# My module
use ROK4::Core::TileMatrixSet;
use ROK4::Core::TileMatrix;
use ROK4::Core::PyramidRaster;
use ROK4::Core::LevelRaster;
use ROK4::Core::Script;
use ROK4::Core::ProxyGDAL;

use ROK4::JOINCACHE::Node;
use ROK4::JOINCACHE::Shell;
use ROK4::JOINCACHE::PropertiesLoader;


################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################
# Pas de bufferisation des sorties.
$|=1;

####################################################################################################
#                                       Group: Variables                                           #
####################################################################################################

# Variable: version
my $VERSION = '@ROK4_VERSION@';

=begin nd
Variable: options

Contains joinCache call options :

    version - To obtain the command's version
    help - To obtain the command's help
    usage - To obtain the command's usage
    properties - Configuration file
=cut
my %options =
(
    "version" => 0,
    "help" => 0,
    "usage" => 0,

    # Configuration
    "properties" => undef, # file properties params (mandatory) !
);

=begin nd
Variable: this

Informations are treated, interpreted and store in this hash, using JOINCACHE classes :

    propertiesLoader - <ROK4::JOINCACHE::PropertiesLoader> - Contains all raw informations
    pyramid - <ROK4::Core::PyramidRaster> - Output pyramid
    mergeMethod - string - Method to use merge slabs when several sources
    useMasks - boolean - do we use masks to generate slabs
    scripts - <ROK4::Core::Script> array - Split scripts to use to generate slabs to merge
    currentScript - integer - Script index to use for the next task (round robin share)
    composition - hash - Defines source pyramids for each level, extent, and order
|       level_id => [
|           { extent => OGR::Geometry, bboxes => [[bbox1], [bbox2]], pyr => ROK4::Core::PyramidRaster}
|           { extent => OGR::Geometry, bboxes => [[bbox1], [bbox2]], pyr => ROK4::Core::PyramidRaster}
|       ]
    listStream - file stream - Open file stream to write the new pyramid list
    roots - hash - Used source pyramids roots (for the list)
    doneSlabs - boolean hash - To memorize already done tiles, we use this hash, containing "I_J => TRUE".
=cut
my %this =
(
    propertiesLoader => undef,

    pyramid => undef,

    mergeMethod => undef,
    useMasks => undef,
    scripts => [],
    jobsNumber => undef,
    currentScript => undef,

    composition => undef,

    listStream => undef,
    roots => {},

    doneSlabs => {}
);

####################################################################################################
#                                         Group: Functions                                         #
####################################################################################################

=begin nd
Function: main

Main method.

See Also:
    <init>, <config>, <validate>, <doIt>
=cut
sub main {
    printf("JOINCACHE : version [%s]\n",$VERSION);

    print STDOUT "BEGIN\n";

    # initialization
    ALWAYS("> Initialization");
    if (! main::init()) {
        print STDERR "ERROR INITIALIZATION !\n";
        exit 1;
    }

    # configuration
    ALWAYS("> Configuration");
    if (! main::config()) {
        print STDERR "ERROR CONFIGURATION !\n";
        exit 2;
    }

    # execution
    ALWAYS("> Validation");
    if (! main::validate()) {
        print STDERR "ERROR VALIDATION !\n";
        exit 3;
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

Checks options and initializes the default logger. Check properties file (mandatory).
=cut
sub init {

    ALWAYS(">>> Check Configuration ...");

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
            printf "See documentation here: https://github.com/rok4/rok4\n" ;
            exit 0;
        },
        "version|v" => sub { exit 0; },
        "usage" => sub {
            printf "See documentation here: https://github.com/rok4/rok4\n" ;
            exit 0;
        },
        
        "properties|conf=s" => \$options{properties},     
    ) or do {
        printf "Unappropriate usage\n";
        printf "See documentation here: https://github.com/rok4/rok4\n";
        exit -1;
    };
  
    # logger by default at runtime
    Log::Log4perl->easy_init({
        level => "WARN",
        layout => '%5p : %m (%M) %n'
    });

    # We make path absolute

    # properties : mandatory !
    if (! defined $options{properties} || $options{properties} eq "") {
        FATAL("Option 'properties' not defined !");
        return FALSE;
    }
    my $fproperties = File::Spec->rel2abs($options{properties});
    $options{properties} = $fproperties;

    return TRUE;
}

=begin nd
Function: config

Load all parameters from the configuration file, using <ROK4::JOINCACHE::PropertiesLoader>.

See Also:
    <checkParams>
=cut
sub config {

    ALWAYS(">>> Load Properties ...");

    my $objProp = ROK4::JOINCACHE::PropertiesLoader->new($options{properties});
    
    if (! defined $objProp) {
        FATAL("Can not load specific properties !");
        return FALSE;
    }

    $this{propertiesLoader} = $objProp;

    ###################

    my $logger = $this{propertiesLoader}->getLoggerSection();
    
    # logger
    if (defined $logger) {
        my @args;

        my $layout= '%5p : %m (%M) %n';
        my $level = $logger->{log_level};

        my $out   = "STDOUT";
        $level = "WARN"   if (! defined $level);

        if ($level =~ /(ALL|DEBUG)/) {
            $layout = '%5p : %m (%M) %n';
        }

        # add the param logger by default (user settings !)
        push @args, {
            file   => $out,
            level  => $level,
            layout => $layout,
        };

        Log::Log4perl->easy_init(@args);
    }

    return TRUE;
}

####################################################################################################
#                                 Group: Validation methods                                        #
####################################################################################################

=begin nd
Function: validate

Validates all components, checks consistency and create scripts. Use classes <ROK4::Core::PyramidRaster>, <ROK4::Core::Script>

See Also:
    <validateSourcePyramids>
=cut
sub validate {

    ##################

    ALWAYS(">>> Create the output ROK4::Core::PyramidRaster object ...");

    my $pyramidSection = $this{propertiesLoader}->getPyramidSection();

    my $objPyramid = ROK4::Core::PyramidRaster->new("VALUES", $pyramidSection);

    if (! defined $objPyramid) {
        ERROR ("Cannot create the ROK4::Core::PyramidRaster object for the output pyramid !");
        return FALSE;
    }

    # Environment variables nécessaire au stockage

    if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables($objPyramid->getStorageType())) {
        ERROR(sprintf "Environment variable is missing for a %s storage", $objPyramid->getStorageType());
        return FALSE;
    }
    
    if (! $objPyramid->bindTileMatrixSet($pyramidSection->{tms_path})) {
        ERROR("Cannot bind TMS to output pyramid");
        return FALSE;
    }

    $this{pyramid} = $objPyramid;

    ################## Process

    ALWAYS(">>> Create the ROK4::Core::Script objects ...");

    my $processSection = $this{propertiesLoader}->getProcessSection();

    $this{mergeMethod} = $processSection->{merge_method};

    if ($objPyramid->ownMasks()) {
        # Si on souhaite avoir des masques dans la pyramide de sortie, il faut les utiliser tout du long des calculs
        $processSection->{use_masks} = "TRUE";
    }

    if (! ROK4::JOINCACHE::Shell::setGlobals($processSection->{job_number}, $processSection->{path_temp}, $processSection->{path_temp_common}, $processSection->{path_shell}, $processSection->{merge_method}, $processSection->{use_masks})) {
        ERROR ("Impossible d'initialiser la librairie des commandes Shell pour JOINCACHE");
        return FALSE;
    }
    my $scriptInit = ROK4::JOINCACHE::Shell::getScriptInitialization($this{pyramid});

    for (my $i = 1; $i <= $processSection->{job_number}; $i++ ) {
        my $script = ROK4::Core::Script->new({
            id => "SCRIPT_$i",
            finisher => FALSE,
            shellClass => 'ROK4::JOINCACHE::Shell',
            initialisation => $scriptInit
        });

        if (! defined $script) {
            ERROR ("Cannot create the ROK4::Core::Script object !");
            return FALSE;
        }

        push(@{$this{scripts}}, $script);
    }

    my $script = ROK4::Core::Script->new({
        id => "SCRIPT_FINISHER",
        finisher => TRUE,
        shellClass => 'ROK4::JOINCACHE::Shell',
        initialisation => $scriptInit
    });

    if (! defined $script) {
        ERROR ("Cannot create the ROK4::Core::Script object !");
        return FALSE;
    }

    push(@{$this{scripts}}, $script);

    $this{currentScript} = 0;
    $this{jobsNumber} = $processSection->{job_number};

    ##################

    ALWAYS(">>> Validate source pyramids ...");

    if (! main::validateSourcePyramids($pyramidSection->{tms_path})) {
        ERROR ("Some source pyramids are not valid !");
        return FALSE;
    }

    ##################

    $this{composition} = $this{propertiesLoader}->getCompositionSection();

    return TRUE;

}

=begin nd
Function: validateSourcePyramids

For each source pyramid (<ROK4::Core::PyramidRaster>), we bind the TMS (<ROK4::Core::PyramidRaster::bindTileMatrixSet>) and we check its compatibility with the output pyramid (<ROK4::Core::PyramidRaster::checkCompatibility>)
=cut
sub validateSourcePyramids {
    my $tms_path = shift;

    my $sourcePyramids = $this{propertiesLoader}->getSourcePyramids();

    foreach my $sourcePyramid (values %{$sourcePyramids}) {

        if (! $sourcePyramid->bindTileMatrixSet($tms_path)) {
            ERROR("Cannot bind TMS to source pyramid " . $sourcePyramid->getName());
            return FALSE;
        }

        if ($sourcePyramid->checkCompatibility($this{pyramid}) == 0) {
            ERROR (sprintf "Source pyramid (%s) and output pyramid are not compatible", $sourcePyramid->getName());
            return FALSE;
        }

        if (! $sourcePyramid->loadList()) {
            ERROR("Cannot cache content list for source pyramid " . $sourcePyramid->getName());
            return FALSE;
        }

        INFO($sourcePyramid->getName());
        INFO($sourcePyramid->getCachedListStats());
    }

    return TRUE;
}

####################################################################################################
#                                 Group: Process methods                                           #
####################################################################################################

=begin nd
Function: doIt

We browse all source pyramids to identify images to generate. 

For each level, for each source pyramid :
    - Identify present images in the extent
    - Work has already been made ? Next
    - Else search it in the other source pyramids with an lower priority
    - Treat source(s) : <main::treatNode>

=cut
sub doIt {

    ALWAYS(">>> Browse source pyramids");

    my $pyramid = $this{pyramid};
    my $TPW = $pyramid->getTilesPerWidth();
    my $TPH = $pyramid->getTilesPerHeight();
    my $TMS = $pyramid->getTileMatrixSet();

    # On stocke la racine de la pyramide de sortie avec l'index 0
    $this{roots}->{$pyramid->getDataRoot()} = 0;

    my $listFile = sprintf "%s/content.list", $this{propertiesLoader}->getProcessSection()->{path_temp_common};
    my $STREAM;
    if (! open $STREAM, ">", $listFile) {
        ERROR(sprintf "Cannot open output pyramid list file (write) : %s",$listFile);
        return FALSE;
    }
    $this{listStream} = $STREAM;

    while( my ($level,$sources) = each(%{$this{composition}}) ) {
        INFO(sprintf "Level %s",$level);

        if (! $pyramid->addLevel($level)) {
            ERROR("Cannot add level $level to output pyramid");
            return FALSE;
        }

        my $tm = $pyramid->getTileMatrixSet()->getTileMatrix($level);

        # On fait une première passe sur les sources pour calculer les indices extrêmes des dalles pour ce niveau pour l'extent de la source
        foreach my $source (@{$sources}) {
            my @a = $source->{pyr}->getLevel($level)->bboxToSlabIndices(@{$source->{bbox}});
            $source->{extrem_slabs} = \@a;
        }

        for (my $n = 0; $n < scalar(@{$sources}); $n++) {
            my $current_source = $sources->[$n];

            my $slabs = $current_source->{pyr}->getLevelSlabs($level);

            # On parcourt toutes les dalles de données de la pyramide source courante
            while (my ($key, $parts) = each(%{$slabs->{DATA}})) {

                if (exists $this{doneSlabs}->{$key}) {
                    # Image already treated
                    next;
                }

                my ($COL, $ROW) = split(/_/, $key);

                # On vérifie que cette dalle appartient bien à l'étendue de la source
                # Si c'est une bbox qui était fournie comme extent, on va économiser un intersect GDAL couteux

                if ($current_source->{provided} eq "WKTFILE") {
                    my @slabBBOX = $current_source->getLevel($level)->slabIndicesToBbox($COL, $ROW);
                    my $slabOGR = ROK4::Core::ProxyGDAL::geometryFromBbox(@slabBBOX);

                    if (! ROK4::Core::ProxyGDAL::isIntersected($slabOGR, $current_source->{extent})) {
                        next;
                    }
                } else {
                    # Extent était une bbox, on va pouvoir plus simplement vérifier les coordonnées des dalles sans passer par GDAL
                    # bboxes dans la source contient forcément une seule bbox, celle fournie.

                    my ($ROWMIN, $ROWMAX, $COLMIN, $COLMAX) = @{$current_source->{extrem_slabs}};

                    if ($COL < $COLMIN || $COL > $COLMAX || $ROW < $ROWMIN || $ROW > $ROWMAX) {
                        next;
                    }
                }

                my @sourceSlabs = ();

                # On traite séparément le cas de la première source principale (la plus prioritaire car :
                #   - on sait que la dalle cherchée appartient à l'extent de cette source (vérifiée juste au dessus)
                #   - si la méthode de fusion est REPLACE, on ne va pas chercher plus loin

                my %sourceSlab = (
                    img => $current_source->{pyr}->containSlab("DATA", $level, $COL, $ROW),
                    msk => undef,
                    compatible => ($pyramid->checkCompatibility($current_source->{pyr}) == 2)
                );

                if ($ROK4::JOINCACHE::Shell::USEMASK) {
                    # Peut être tout de même non défini
                    $sourceSlab{msk} = $current_source->{pyr}->containSlab("MASK", $level, $COL, $ROW);
                }

                push(@sourceSlabs, \%sourceSlab);

                if ($ROK4::JOINCACHE::Shell::MERGEMETHOD ne 'REPLACE') {
                    # On doit regarder dans les sources suivantes si la dalle y est aussi,
                    # sauf dans le cas REPLACE où seule la dalle du dessus est considérée
                    for (my $m = $n + 1; $m < scalar(@{$sources}); $m++) {
                        my $next_source = $sources->[$m];

                        # On commence par regarder si cette source suivante possède la dalle
                        if (! defined $next_source->{pyr}->containSlab("DATA", $level, $COL, $ROW)) {
                            next;
                        }

                        # De même que pour la source courante, on regarde si la dalle appartient à l'étendue d'utilisation de cette source
                        if ($next_source->{provided} eq "WKTFILE") {
                            my @slabBBOX = $next_source->getLevel($level)->slabIndicesToBbox($COL, $ROW);
                            my $slabOGR = ROK4::Core::ProxyGDAL::geometryFromBbox(@slabBBOX);

                            if (! ROK4::Core::ProxyGDAL::isIntersected($slabOGR, $next_source->{extent})) {
                                next;
                            }
                        } else {
                            my ($ROWMIN, $ROWMAX, $COLMIN, $COLMAX) = @{$next_source->{extrem_slabs}};

                            if ($COL < $COLMIN || $COL > $COLMAX || $ROW < $ROWMIN || $ROW > $ROWMAX) {
                                next;
                            }
                        }

                        my %sourceSlab = (
                            img => $next_source->{pyr}->containSlab("DATA", $level, $COL, $ROW),
                            msk => undef,
                            compatible => ($pyramid->checkCompatibility($next_source->{pyr}) == 2)
                        );

                        if ($ROK4::JOINCACHE::Shell::USEMASK) {
                            # Peut être tout de même non défini
                            $sourceSlab{msk} = $next_source->{pyr}->containSlab("MASK", $level, $COL, $ROW);
                        }

                        push(@sourceSlabs, \%sourceSlab);
                    }
                }

                my $node = ROK4::JOINCACHE::Node->new({
                    level => $level,
                    col => $COL,
                    row => $ROW,
                    pyramid => $pyramid,
                    sources => \@sourceSlabs
                });

                if (! main::treatNode($node)) {
                    ERROR(sprintf "Cannot generate the node %s", Dumper($node));
                    return FALSE;
                }
                
                $pyramid->getLevel($level)->updateLimitsFromSlab($COL, $ROW);
                $this{doneSlabs}->{$key} = TRUE;
            }

        }

        delete $this{doneSlabs};
    }

    close($this{listStream});

    # On ferme tous les scripts
    foreach my $s (@{$this{scripts}}) {
        $s->close();
    }

    # We write at the top of the list file, caches' roots, using Tie library
    my @LIST;
    if (! tie @LIST, 'Tie::File', $listFile) {
        ERROR("Cannot open '$listFile' with Tie librairy");
        return FALSE;
    }

    unshift @LIST, "#\n";
    while( my ($root,$rootID) = each( %{$this{roots}} ) ) {
        if ($rootID == 0) {next;}
        unshift @LIST, "$rootID=$root\n";
    }

    # Root of the new cache (first position)
    unshift @LIST,(sprintf "0=%s\n", $this{pyramid}->getDataRoot());

    untie @LIST;

    # writting pyramid's configuration file
    ALWAYS(">>> Write pyramid's descriptor");
    if (! $pyramid->writeDescriptor()) {
        ERROR("Can not write Pyramid descriptor !");
        return FALSE;
    }

    # Écrire le script principal
    ALWAYS(">>> Write main script");
    my $scriptPath = File::Spec->catfile($this{propertiesLoader}->getProcessSection()->{path_shell}, "main.sh");
    open(MAIN, ">$scriptPath") or do {
        ERROR("Cannot open '$scriptPath' to write in it");
        return FALSE;
    };

    print MAIN ROK4::JOINCACHE::Shell::getMainScript();

    close(MAIN);

    INFO("To run all scripts on the same machine, run :");
    INFO("\t bash $scriptPath");

    return TRUE;
}

sub treatNode {
    my $node = shift;

    # On affecte le script courant au noeud.
    $node->setScript( $this{scripts}->[$this{currentScript}] );
    $this{currentScript} = ( $this{currentScript} + 1 ) % ( $this{jobsNumber} );

    if ($node->getSourcesNumber() == 1) {

        my $sourceImage = $node->getSource(0);

        if ($sourceImage->{compatible}) {
            # We can just make a symbolic link, in a script
            $node->linkSlab($sourceImage->{img}->[0], $sourceImage->{img}->[1]);
            # Les cibles des liens sont ajoutées dans la liste directement
            main::storeInList($sourceImage->{img}->[0], $sourceImage->{img}->[1]);
        } else {
            # We have just one source image, but it is not compatible with the final cache
            # We need to transform it (pull push).
            if ( ! $node->convert() ) {
                ERROR(sprintf "Cannot transform the image");
                return FALSE;
            }
            # C'est à l'exécution de la commande de conversion que la nouvelle dalle sera ajoutée dans la liste
        }

        # Export éventuel du masque : il est forcément dans le bon format, on peut donc le lier.
        if (defined $sourceImage->{msk} && $this{pyramid}->ownMasks()) {
            # We can just make a symbolic link, in a script
            $node->linkSlab($sourceImage->{msk}->[0], $sourceImage->{msk}->[1]);
            main::storeInList($sourceImage->{msk}->[0], $sourceImage->{msk}->[1]);
        }
        
    } else {
        # We have several images, we merge them
        if ( ! $node->overlayNtiff() ) {
            ERROR(sprintf "Cannot merge the images");
            return FALSE;
        }
        # C'est à l'exécution de la commande de superposition que la nouvelle dalle sera ajoutée dans la liste
    }

    return TRUE;
}

####################################################################################################
#                                   Group: List methods                                            #
####################################################################################################

=begin nd
Function: storeInList

Writes slab's path in the pyramid's content list and store the root.

Parameters:
    root - string - Root of slab to list.
    slab - string - Name of the slab to list
=cut
sub storeInList {
    my $root = shift;
    my $slab = shift;

    my $rootID;
    if (exists $this{roots}->{$root}) {
        $rootID = $this{roots}->{$root};
    } else {
        $rootID = scalar (keys %{$this{roots}});
        $this{roots}->{$root} = $rootID;
    }

    my $STREAM = $this{listStream};
    printf $STREAM "%s\n", "$rootID/$slab";
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
