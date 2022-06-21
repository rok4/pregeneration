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
use ROK4::PREGENERATION::Script;
use ROK4::PREGENERATION::Source;
use ROK4::Core::ProxyGDAL;

use ROK4::JOINCACHE::Node;
use ROK4::JOINCACHE::Shell;
use ROK4::JOINCACHE::Validator;


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
my $VERSION = '@VERSION@';

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

Informations are treated, interpreted and store in this hash
=cut
my %this =
(
    params => undef,
    loaded => {
        output_pyramid => undef,
        merge_method => undef,
        sources => [],
        levels => { }
    },
    work => {
        list_stream => undef,
        current_script => undef,
        roots => {},
        scripts => [],
        done_slabs => {}
    },
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
    ALWAYS("> Loading");
    if (! main::load()) {
        print STDERR "ERROR LOADING !\n";
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

Load all parameters from the configuration file, and validate using <ROK4::JOINCACHE::Validator::validate>.

See Also:
    <checkParams>
=cut
sub config {
    
    $this{params} = ROK4::Core::Utils::get_hash_from_json_file($options{properties});
    
    if (! defined $this{params}) {
        ERROR("Can not load properties !");
        return FALSE;
    }
    
    ###################
    # check parameters
    
    if (! ROK4::JOINCACHE::Validator::validate($this{params})) {
        ERROR("Invalid configuration");
        return FALSE;
    }

    my $logger = $this{params}->{logger};
    
    # logger
    if (defined $logger) {
        
        my $layout = '%5p : %m (%M) %n';
        if (defined $logger->{layout}) {
            $layout = $logger->{layout};
        }

        my $level = "WARN";
        if (defined $logger->{level}) {
            $level = $logger->{level};
        }

        my $out = "STDOUT";
        if (defined $logger->{file}) {
            $out = ">>".$logger->{file};
        }

        Log::Log4perl->easy_init({
            file   => $out,
            level  => $level,
            layout => $layout,
        });
    }
    
    return TRUE;
}

=begin nd
Function: load

Load and validate all components, checks consistency and create scripts.
=cut
sub load {

    ####################### LOAD SOURCES

    ALWAYS(">>> Load data sources...");

    my $datasources = $this{params}->{datasources};

    my $refPyramid = undef;
    foreach my $ds (@{$datasources}) {
        my $objSource = ROK4::PREGENERATION::Source->new($ds);
        if (! defined $objSource) {
            ERROR("Cannot load one PYRAMIDS data source");
            return FALSE;
        }
        my $sourceType = $objSource->getType();
        if ($sourceType ne "PYRAMIDS") {
            ERROR("JOINCACHE generation accept only PYRAMIDS sources");
            return FALSE;
        }
        push(@{$this{loaded}->{sources}}, $objSource);

        if (! defined $refPyramid) {
            $refPyramid = $objSource->getSource()->getPyramids()->[0];
        } elsif ($refPyramid->checkCompatibility($objSource->getSource()->getPyramids()->[0]) == 0) {
            ERROR("Different PYRAMIDS sources have to be consistent");
            return FALSE;
        }
    }

    # On regarde si on peut extraire un seul type de pixel, ce qui permet de ne pas fournir celui de la pyramide en sortie
    # Cela implique
    my $inputPixel = undef;
    foreach my $s (@{$this{loaded}->{sources}}) {
        if (! defined $s->getPixel()) {
            # Deux pyramides de la source n'ont déjà pas les mếme caractéristiques
            INFO("All source pyramids does not own the same pixel informations, we have to provide the output pixel");
            last;
        }
        if (! defined $inputPixel) {
            $inputPixel = $s->getPixel();
        } elsif (! $inputPixel->equals($s->getPixel())) {
            INFO("All source pyramids does not own the same pixel informations, we have to provide the output pixel");
            last;
        }
    }

    ####################### LOAD OUTPUT

    ALWAYS(">>> Load the pyramid to generate ...");

    # Les caractéristiques de la pyramide en sortie sont en grande partie récupérées des pyramides en entrée

    if (defined $inputPixel) {
        if (! exists $this{params}->{pyramid}->{pixel}->{sampleformat}) {
            $this{params}->{pyramid}->{pixel}->{sampleformat} = $inputPixel->getSampleFormatCode();
        }
        if (! exists $this{params}->{pyramid}->{pixel}->{samplesperpixel}) {
            $this{params}->{pyramid}->{pixel}->{samplesperpixel} = $inputPixel->getSamplesPerPixel();
        }
    }
    $this{params}->{pyramid}->{slab_size} = [$refPyramid->getTilesPerWidth(), $refPyramid->getTilesPerHeight()];
    $this{params}->{pyramid}->{tms} = $refPyramid->getTileMatrixSet()->getName();
    $this{params}->{pyramid}->{storage}->{type} = $refPyramid->getStorageType();

    if ($this{params}->{pyramid}->{storage}->{type} eq "FILE") {
        # Dans le cas du stockage fichier, la profondeur d'arborescence est la même que pour les sources
        $this{params}->{pyramid}->{storage}->{depth} = $refPyramid->getDirDepth();
    }

    $this{loaded}->{output_pyramid} = ROK4::Core::PyramidRaster->new("VALUES", $this{params}->{pyramid} );
    if (! defined $this{loaded}->{output_pyramid}) {
        ERROR("Cannot load new pyramid");
        return FALSE;
    }

    if ($this{loaded}->{output_pyramid}->checkCompatibility($refPyramid) == 0) {
        ERROR("Output pyramid is not consistent with input pyramids");
        return FALSE;
    }

    ####################### MANAGE SOURCES

    # On va réorganiser les sources par niveaux, pour faciliter les traitements ensuite

    my $tms = $this{loaded}->{output_pyramid}->getTileMatrixSet();
    foreach my $s (@{$this{loaded}->{sources}}) {
        my $pyramids = $s->getSource()->getPyramids();

        my $topID = $s->getTopID();
        my $topOrder = $tms->getOrderfromID($topID);
        $s->setTopOrder($topOrder);

        my $bottomID = $s->getBottomID();
        my $bottomOrder = $tms->getOrderfromID($bottomID);
        $s->setBottomOrder($bottomOrder);

        for (my $order = $bottomOrder; $order <= $topOrder; $order++) {
            my $ID = $tms->getIDfromOrder($order);

            if (! exists $this{loaded}->{levels}->{$ID}) {
                $this{loaded}->{levels}->{$ID} = [];
            }            

            if (! $this{loaded}->{output_pyramid}->addLevel($ID) ) {
                ERROR("Cannot add level $ID");
                return FALSE;
            }

            for my $p (@{$pyramids}) {
                
                if (! $p->loadList()) {
                    ERROR("Cannot cache content list for source pyramid " . $p->getName());
                    return FALSE;
                }

                my $elem = {
                    pyramid => $p,
                    compatible => $this{loaded}->{output_pyramid}->checkCompatibility($p)
                };

                if ($s->getArea() eq "BBOX") {
                    $elem->{bbox} = $s->getBbox();
                }
                elsif ($s->getArea() eq "EXTENT") {
                    $elem->{extent} = $s->getExtent();
                }

                my @a = $p->getLevel($ID)->bboxToSlabIndices(@{$s->getBbox()});
                $elem->{extrem_slabs} = \@a;

                push( @{$this{loaded}->{levels}->{$ID}}, $elem);
            }
        }
    }

    ####################### LOAD SCRIPTS

    if ($this{loaded}->{output_pyramid}->ownMasks()) {
        # Si on souhaite avoir des masques dans la pyramide de sortie, il faut les utiliser tout du long des calculs
        $this{params}->{process}->{mask} = 1;
    }

    if (! ROK4::JOINCACHE::Shell::setGlobals($this{params}->{process})) {
        ERROR ("Impossible d'initialiser la librairie des commandes Shell pour JOINCACHE");
        return FALSE;
    }
    my $scriptInit = ROK4::JOINCACHE::Shell::getScriptInitialization($this{loaded}->{output_pyramid});

    for (my $i = 1; $i <= $this{params}->{process}->{parallelization}; $i++ ) {
        my $script = ROK4::PREGENERATION::Script->new({
            id => "SCRIPT_$i",
            finisher => FALSE,
            shellClass => 'ROK4::JOINCACHE::Shell',
            initialisation => $scriptInit
        });

        if (! defined $script) {
            ERROR ("Cannot create the ROK4::PREGENERATION::Script object !");
            return FALSE;
        }

        push(@{$this{work}->{scripts}}, $script);
    }

    my $script = ROK4::PREGENERATION::Script->new({
        id => "SCRIPT_FINISHER",
        finisher => TRUE,
        shellClass => 'ROK4::JOINCACHE::Shell',
        initialisation => $scriptInit
    });

    if (! defined $script) {
        ERROR ("Cannot create the ROK4::PREGENERATION::Script object !");
        return FALSE;
    }

    push(@{$this{work}->{scripts}}, $script);

    $this{work}->{current_script} = 0;

    return TRUE;

}

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

    # On stocke la racine de la pyramide de sortie avec l'index 0
    my $pyramid = $this{loaded}->{output_pyramid};
    my $tms = $pyramid->getTileMatrixSet();
    $this{work}->{roots}->{$pyramid->getDataRoot()} = 0;

    my $listFile = sprintf "%s/content.list", $ROK4::JOINCACHE::Shell::COMMONTEMPDIR;
    my $STREAM;
    if (! open $STREAM, ">", $listFile) {
        ERROR(sprintf "Cannot open output pyramid list file (write) : %s",$listFile);
        return FALSE;
    }
    $this{work}->{list_stream} = $STREAM;

    while( my ($level, $sources) = each(%{$this{loaded}->{levels}}) ) {
        INFO(sprintf "Level %s",$level);

        my $tm = $tms->getTileMatrix($level);

        for (my $n = 0; $n < scalar(@{$sources}); $n++) {
            my $current_source = $sources->[$n];
            my $slabs = $current_source->{pyramid}->getLevelSlabs($level);

            # On parcourt toutes les dalles de données de la pyramide source courante
            while (my ($key, $parts) = each(%{$slabs->{DATA}})) {

                if (exists $this{work}->{done_slabs}->{$key}) {
                    # Image already treated
                    next;
                }

                my ($COL, $ROW) = split(/_/, $key);

                # On vérifie que cette dalle appartient bien à l'étendue de la source
                # Si c'est une bbox qui était fournie comme extent, on va économiser un intersect GDAL couteux

                if (exists $current_source->{extent}) {
                    my @slabBBOX = $current_source->{pyramid}->getLevel($level)->slabIndicesToBbox($COL, $ROW);
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
                    img => $current_source->{pyramid}->containSlab("DATA", $level, $COL, $ROW),
                    msk => undef,
                    compatible => ($current_source->{compatible} == 2)
                );

                if ($ROK4::JOINCACHE::Shell::USEMASK) {
                    # Peut être tout de même non défini
                    $sourceSlab{msk} = $current_source->{pyramid}->containSlab("MASK", $level, $COL, $ROW);
                }

                push(@sourceSlabs, \%sourceSlab);

                if ($ROK4::JOINCACHE::Shell::MERGEMETHOD ne 'REPLACE') {
                    # On doit regarder dans les sources suivantes si la dalle y est aussi,
                    # sauf dans le cas REPLACE où seule la dalle du dessus est considérée
                    for (my $m = $n + 1; $m < scalar(@{$sources}); $m++) {
                        my $next_source = $sources->[$m];

                        # On commence par regarder si cette source suivante possède la dalle
                        if (! defined $next_source->{pyramid}->containSlab("DATA", $level, $COL, $ROW)) {
                            next;
                        }

                        # De même que pour la source courante, on regarde si la dalle appartient à l'étendue d'utilisation de cette source
                        if (exists $next_source->{extent}) {
                            my @slabBBOX = $next_source->{pyramid}->getLevel($level)->slabIndicesToBbox($COL, $ROW);
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
                            img => $next_source->{pyramid}->containSlab("DATA", $level, $COL, $ROW),
                            msk => undef,
                            compatible => ($next_source->{compatible} == 2)
                        );

                        if ($ROK4::JOINCACHE::Shell::USEMASK) {
                            # Peut être tout de même non défini
                            $sourceSlab{msk} = $next_source->{pyramid}->containSlab("MASK", $level, $COL, $ROW);
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
                $this{work}->{done_slabs}->{$key} = TRUE;
            }

        }

        delete $this{work}->{done_slabs};
    }

    close($this{work}->{list_stream});

    # On ferme tous les scripts
    foreach my $s (@{$this{work}->{scripts}}) {
        $s->close();
    }

    # We write at the top of the list file, caches' roots, using Tie library
    my @LIST;
    if (! tie @LIST, 'Tie::File', $listFile) {
        ERROR("Cannot open '$listFile' with Tie librairy");
        return FALSE;
    }

    unshift @LIST, "#\n";
    while( my ($root,$rootID) = each( %{$this{work}->{roots}} ) ) {
        if ($rootID == 0) {next;}
        unshift @LIST, "$rootID=$root\n";
    }

    # Root of the new cache (first position)
    unshift @LIST,(sprintf "0=%s\n", $pyramid->getDataRoot());

    untie @LIST;

    # writting pyramid's configuration file
    ALWAYS(">>> Write pyramid's descriptor");
    if (! $pyramid->writeDescriptor()) {
        ERROR("Can not write Pyramid descriptor !");
        return FALSE;
    }

    # Écrire le script principal
    ALWAYS(">>> Write main script");
    my $scriptPath = File::Spec->catfile($ROK4::JOINCACHE::Shell::SCRIPTSDIR, "main.sh");
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


    # work => {
    #     list_stream => undef,
    #     current_script => undef,
    #     roots => {},
    #     scripts => [],
    #     done_slabs => {}
    # },

sub treatNode {
    my $node = shift;

    # On affecte le script courant au noeud.
    $node->setScript( $this{work}->{scripts}->[$this{work}->{current_script}] );
    $this{work}->{current_script} = ( $this{work}->{current_script} + 1 ) % ( $this{params}->{process}->{parallelization} );

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
        if (defined $sourceImage->{msk} && $this{loaded}->{output_pyramid}->ownMasks()) {
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
    if (exists $this{work}->{roots}->{$root}) {
        $rootID = $this{work}->{roots}->{$root};
    } else {
        $rootID = scalar (keys %{$this{work}->{roots}});
        $this{work}->{roots}->{$root} = $rootID;
    }

    my $STREAM = $this{work}->{list_stream};
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
