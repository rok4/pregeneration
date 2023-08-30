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
File: be4.pl
=cut

################################################################################

use warnings;
use strict;

use POSIX qw(locale_h);

use Getopt::Long;

use Data::Dumper;
#local $Data::Dumper::Maxdepth = 2;

use File::Basename;
use File::Spec;
use File::Path;
use Cwd;

use Log::Log4perl qw(:easy);

# My search module
use FindBin qw($Bin);
use lib "$Bin/../lib/perl5";

# My module
use ROK4::Core::PyramidRaster;
use ROK4::BE4::Validator;
use ROK4::PREGENERATION::Source;
use ROK4::PREGENERATION::Forest;
use ROK4::Core::Array;
use ROK4::Core::Utils;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

my %UPDATESMODES = (
    "FILE" => ["slink", "hlink", "copy" ],
    "S3" => ["slink", "copy" ],
    "SWIFT" => ["slink", "copy" ],
    "CEPH" => ["slink", "copy" ]
);

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

Contains be4 call options :

    version - To obtain the command's version
    help - To obtain the command's help
    usage - To obtain the command's usage
    properties - Configuration file
=cut
my %options =
(
    "version"    => 0,
    "help"       => 0,
    "usage"      => 0,
    
    # Configuration
    "properties"  => undef, # file properties params (mandatory) !
);

=begin nd
Variable: this
=cut
my %this =
(
    params => undef,
    loaded => {
        input_pyramid => undef,
        output_pyramid => undef,
        forest => undef,
        update_mode => undef,
        sources => []
    }
);

####################################################################################################
#                                         Group: Functions                                         #
####################################################################################################

=begin nd
Function: main

Main method.

See Also:
    <init>, <config>, <doIt>
=cut
sub main {
    printf("BE4: version [%s]\n",$VERSION);
    # message
    my $message = undef;

    # initialization
    ALWAYS("> Initialization");
    if (! main::init()) {
        $message = "ERROR INITIALIZATION !";
        printf STDERR "%s\n", $message;
        exit 1;
    }

    $message = "BEGIN";
    printf STDOUT "%s\n", $message;

    # configuration
    ALWAYS("> Configuration");
    if (! main::config()) {
        $message = "ERROR CONFIGURATION !";
        printf STDERR "%s\n", $message;
        exit 2;
    }

    # execution
    ALWAYS("> Execution");
    if (! main::doIt()) {
        $message = "ERROR EXECUTION !";
        printf STDERR "%s\n", $message;
        exit 3;
    }

    $message = "END";
    printf STDOUT "%s\n", $message;
}

=begin nd
Function: init

Checks options and initializes the default logger. Check properties file (mandatory).
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
            printf "See documentation here: https://github.com/rok4/pregeneration\n" ;
            exit 0;
        },
        "version|v" => sub { exit 0; },
        "usage" => sub {
            printf "See documentation here: https://github.com/rok4/pregeneration\n" ;
            exit 0;
        },
        
        "properties|conf=s" => \$options{properties}
    ) or do {
        printf "Unappropriate usage\n";
        printf "See documentation here: https://github.com/rok4/pregeneration\n";
        exit -1;
    };
  
    # logger by default at runtime
    Log::Log4perl->easy_init({
        level => $WARN,
        layout => '%5p : %m (%M) %n'
    });

    # We make path absolute

    # properties : mandatory !
    if (! defined $options{properties} || $options{properties} eq "") {
        ERROR("Option 'properties' not defined !");
        return FALSE;
    }
    my $fproperties = File::Spec->rel2abs($options{properties});
    $options{properties} = $fproperties;
    
    return TRUE;
}

=begin nd
Function: config

Loads properties files and validate using <ROK4::BE4::Validator::validate>.
=cut
sub config {

    ###################
    ALWAYS(">>> Load Properties ...");
    
    $this{params} = ROK4::Core::Utils::get_hash_from_json_file($options{properties});
    
    if (! defined $this{params}) {
        ERROR("Can not load properties !");
        return FALSE;
    }
    
    ###################
    # check parameters
    
    if (! ROK4::BE4::Validator::validate($this{params})) {
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
Function: writeListAndReferences
=cut
sub writeListAndReferences {

    my $storageType = $this{loaded}->{output_pyramid}->getStorageType();
    my $newListPath = File::Spec->catfile($ROK4::BE4::Shell::COMMONTEMPDIR, "content.list");
    my $newRoot = $this{loaded}->{output_pyramid}->getDataRoot();
    my $updateMode = $this{loaded}->{update_mode};

    my $NEWLIST;

    if (! open $NEWLIST, ">", $newListPath) {
        ERROR(sprintf "Cannot open new pyramid list file (write) : %s",$newListPath);
        return FALSE;
    }
    
    if ($this{params}->{pyramid}->{type} eq "GENERATION") {
        # La pyramide en sortie est nouvelle, sans ancêtre
        print $NEWLIST "0=$newRoot\n";
        print $NEWLIST "#\n";
        close $NEWLIST;
        return TRUE
    }

    ############################## LA PYRAMIDE EN SORTIE A DU CONTENU #######################################
    # Soit par référence des dalles d'un ancêtre
    # Soit parce que la pyramide en sortie existe déjà (injection)

    # On va lire la liste de la pyramide en entrée (à référencer ou égale à celle en sortie)
    if (! $this{loaded}->{input_pyramid}->loadList()) {
        ERROR("Cannot cache content list of the ancestor pyramid");
        return FALSE;
    }

    my $slabs = $this{loaded}->{input_pyramid}->getLevelsSlabs();
    my $rootsNumber = 1;
    my %roots = (
        $newRoot => 0
    );

    while( my ($level, $levelSlabs) = each(%{$slabs}) ) {

        while( my ($key, $parts) = each(%{$slabs->{$level}->{DATA}}) ) {
            my $r = $parts->{root};
            my $t = $parts->{name};
            my ($col,$row) = split("_", $key);

            if ($updateMode eq "slink") {
                if (! defined ROK4::Core::ProxyStorage::symLink($storageType, "$r/$t", $storageType, "$newRoot/$t")) {
                    ERROR("The ancestor slab '$r/$t' cannot be referenced by sym link in the new pyramid");
                    return FALSE;
                }
            }
            elsif ($updateMode eq "hlink") {
                if (! ROK4::Core::ProxyStorage::hardLink($storageType, "$r/$t", $storageType, "$newRoot/$t")) {
                    ERROR("The ancestor slab '$r/$t' cannot be referenced by hard link in the new pyramid");
                    return FALSE;
                }
            }
            elsif ($updateMode eq "copy") {
                if (! ROK4::Core::ProxyStorage::copy($storageType, "$r/$t", $storageType, "$newRoot/$t")) {
                    ERROR("The ancestor slab '$r/$t' cannot be copy in the new pyramid");
                    return FALSE;
                }
            }

            if (! $this{loaded}->{forest}->containsNode($level,$col,$row)) {

                if ($updateMode eq 'slink' || $updateMode eq 'inject') {
                    # Dans le cas injectif ou lien symbolique, on a laissé le fichier ou lien tel quel, on remet donc la ligne telle quelle
                    my $rootInd;
                    if (! exists $roots{$r}) {
                        $roots{$r} = $rootsNumber;
                        $rootInd = $rootsNumber;
                        $rootsNumber++;
                    } else {
                        $rootInd = $roots{$r};
                    }
                    print $NEWLIST "$rootInd/$t\n";
                } else {
                    print $NEWLIST "0/$t\n";
                }
            }
        }

        if (exists $slabs->{$level}->{MASK}) {
            while( my ($key, $parts) = each(%{$slabs->{$level}->{MASK}}) ) {
                my $r = $parts->{root};
                my $t = $parts->{name};
                my ($col,$row) = split("_", $key);

                if ($updateMode eq "slink") {
                    if (! defined ROK4::Core::ProxyStorage::symLink($storageType, "$r/$t", $storageType, "$newRoot/$t")) {
                        ERROR("The ancestor slab '$r/$t' cannot be referenced by sym link in the new pyramid");
                        return FALSE;
                    }
                }
                elsif ($updateMode eq "hlink") {
                    if (! ROK4::Core::ProxyStorage::hardLink($storageType, "$r/$t", $storageType, "$newRoot/$t")) {
                        ERROR("The ancestor slab '$r/$t' cannot be referenced by hard link in the new pyramid");
                        return FALSE;
                    }
                }
                elsif ($updateMode eq "copy") {
                    if (! ROK4::Core::ProxyStorage::copy($storageType, "$r/$t", $storageType, "$newRoot/$t")) {
                        ERROR("The ancestor slab '$r/$t' cannot be copy in the new pyramid");
                        return FALSE;
                    }
                }

                if (! $this{loaded}->{forest}->containsNode($level,$col,$row)) {

                    if ($updateMode eq 'slink' || $updateMode eq 'inject') {
                        # Dans le cas injectif ou lien symbolique, on a laissé le fichier ou lien tel quel, on remet donc la ligne telle quelle
                        my $rootInd;
                        if (! exists $roots{$r}) {
                            $roots{$r} = $rootsNumber;
                            $rootInd = $rootsNumber;
                            $rootsNumber++;
                        } else {
                            $rootInd = $roots{$r};
                        }
                        print $NEWLIST "$rootInd/$t\n";
                    } else {
                        print $NEWLIST "0/$t\n";
                    }
                }
            }
        }

    }

    close $NEWLIST;

    # Now, we can write binding between ID and root, testing counter.
    # We write at the top of the list file, caches' roots, using Tie library
    my @NEWLISTHDR;
    if (! tie @NEWLISTHDR, 'Tie::File', $newListPath) {
        ERROR("Cannot write the header of the new pyramid temporary list file : $newListPath");
        return FALSE;
    }

    unshift @NEWLISTHDR,"#\n";
    
    while ( my ($root, $rootID) = each(%roots) ) {
        if ($rootID == 0) {
            # La racine de la pyramide en sortie sera ajoutée après, pour être en première ligne
            next;
        }
        unshift @NEWLISTHDR,(sprintf "%s=%s", $rootID, $root);
    }
    
    unshift @NEWLISTHDR,"0=$newRoot\n";
    untie @NEWLISTHDR;
    
    return TRUE;
}

=begin nd
Function: doIt
=cut
sub doIt {

    #######################
    # link to parameters
    my $params = $this{params};

    ####################### LOAD SOURCES
    
    ALWAYS(">>> Load data sources...");

    my $datasources = $this{params}->{datasources};

    my $inputPixel = undef;
    foreach my $ds (@{$datasources}) {
        my $objSource = ROK4::PREGENERATION::Source->new($ds);
        if (! defined $objSource) {
            ERROR("Cannot load one data source");
            return FALSE;
        }
        my $sourceType = $objSource->getType();
        if ($sourceType ne "IMAGES" && $sourceType ne "WMS") {
            ERROR("BE4 generation accept only IMAGES or WMS sources");
            return FALSE;
        }
        push(@{$this{loaded}->{sources}}, $objSource);
        if ($sourceType eq "IMAGES") {
            my $pix = $objSource->getPixel();
            if (! defined $inputPixel) {
                $inputPixel = $pix;
                next;
            }
            if (! $pix->equals($inputPixel)) {
                ERROR("We have several images sources but pixel caracteristics are different, we can't extract ONE format from sources for output");
                return FALSE;
            }
        }
    }

    ####################### PYRAMIDES

    my $pyramid = $this{params}->{pyramid};

    my $storageType = undef;

    if ($pyramid->{type} eq "INJECTION") {
        ALWAYS(">>> Load the pyramid to inject ...");
        $this{loaded}->{output_pyramid} = ROK4::Core::PyramidRaster->new("DESCRIPTOR", $pyramid->{pyramid_to_inject} );
        if (! defined $this{loaded}->{output_pyramid}) {
            ERROR("Cannot load pyramid to inject");
            return FALSE;
        }
        $this{loaded}->{update_mode} = "inject";

        # La pyramide en sortie peut aussi être considérée comme en entrée
        $this{loaded}->{input_pyramid} = $this{loaded}->{output_pyramid};

        $storageType = $this{loaded}->{output_pyramid}->getStorageType();
    }
    elsif ($pyramid->{type} eq "UPDATE") {
        ALWAYS(">>> Load the pyramid to update ...");

        $this{loaded}->{input_pyramid} = ROK4::Core::PyramidRaster->new("DESCRIPTOR", $pyramid->{pyramid_to_update} );
        if (! defined $this{loaded}->{input_pyramid}) {
            ERROR("Cannot load pyramid to update");
            return FALSE;
        }
        $storageType = $this{loaded}->{input_pyramid}->getStorageType();

        $this{loaded}->{update_mode} = $pyramid->{update_mode};
        if (! defined $this{loaded}->{update_mode}) {
            $this{loaded}->{update_mode} = "slink";
        }
        if (! defined ROK4::Core::Array::isInArray($this{loaded}->{update_mode}, @{$UPDATESMODES{$storageType}}) ) {
            ERROR(sprintf "Update mode '%s' is not allowed for $storageType pyramids", $this{loaded}->{update_mode});
            return FALSE;
        }

        if ($pyramid->{name} eq $this{loaded}->{input_pyramid}->getName()) {
            ERROR(sprintf "The new update pyramid name cannot be the same as the pyramid to update");
            return FALSE;
        }

        $this{loaded}->{output_pyramid} = $this{loaded}->{input_pyramid}->clone($pyramid->{name}, $pyramid->{root});
    }
    elsif ($pyramid->{type} eq "GENERATION") {
        ALWAYS(">>> Load the pyramid to generate ...");

        if (defined $inputPixel) {
            if (! exists $pyramid->{pixel}->{sampleformat}) {
                $pyramid->{pixel}->{sampleformat} = $inputPixel->getSampleFormatCode();
            }
            if (! exists $pyramid->{pixel}->{samplesperpixel}) {
                $pyramid->{pixel}->{samplesperpixel} = $inputPixel->getSamplesPerPixel();
            }
        }

        if (! exists $pyramid->{nodata}) {
            $pyramid->{nodata} = [];

            for (my $i = 0; $i < $pyramid->{pixel}->{samplesperpixel}; $i++) {
                if ($pyramid->{pixel}->{sampleformat} eq "FLOAT32") {
                    push(@{$pyramid->{nodata}}, -99999);
                } elsif ($pyramid->{pixel}->{sampleformat} eq "UINT8") {
                    push(@{$pyramid->{nodata}}, 255);
                } else {
                    push(@{$pyramid->{nodata}}, 0);
                }
            }
        }  

        $this{loaded}->{output_pyramid} = ROK4::Core::PyramidRaster->new("VALUES", $pyramid );
        if (! defined $this{loaded}->{output_pyramid}) {
            ERROR("Cannot load new pyramid");
            return FALSE;
        }

        $storageType = $this{loaded}->{output_pyramid}->getStorageType();
    }

    # On copie le type de génération de pyramide dans la section process
    $params->{process}->{type} = $pyramid->{type};

    if ($this{loaded}->{output_pyramid}->ownMasks()) {
        # Si on souhaite avoir des masques dans la pyramide de sortie, il faut les utiliser tout du long des calculs
        $params->{process}->{mask} = 1;
    }

    ####################### UPDATE SOURCES

    ALWAYS(">>> Update sources' levels ...");

    my $tms = $this{loaded}->{output_pyramid}->getTileMatrixSet();

    # On détermine les niveaux du bas <AUTO>
    foreach my $s (@{$this{loaded}->{sources}}) {
        my $bottomID = $s->getBottomID();
        if ($bottomID eq "<AUTO>") {
            $bottomID = $tms->getBestLevelID($s->getSource()->getBestResImage());
            if (! defined $bottomID) {
                ERROR(sprintf "Cannot auto detect the bottom level from image source best resolution");
                return FALSE;
            }
            DEBUG("Bottom level auto detection from source images resolution : $bottomID");
            $s->setBottomID($bottomID);
        }
        my $bottomOrder = $tms->getOrderfromID($bottomID);
        if (! defined $bottomOrder) {
            ERROR(sprintf "The bottom level $bottomID in a source does not exist in the TMS");
            return FALSE;
        }
        $s->setBottomOrder($bottomOrder);
    }

    # On met les sources dans l'ordre, du bas vers le haut
    my @orderedSources = sort {$a->getBottomOrder() <=> $b->getBottomOrder()} (@{$this{loaded}->{sources}});


    my %orders;
    my $globalTopOrder = undef;
    my $globalBottomOrder = undef;

    for (my $i = 0; $i < scalar(@orderedSources); $i++) {
        my $s = $orderedSources[$i];

        my $bottomID = $s->getBottomID();
        my $bottomOrder = $s->getBottomOrder();

        my $topID = $s->getTopID();
        if ($topID eq "<AUTO>") {
            if ($i == scalar(@orderedSources) - 1) {
                # On est sur la source utilisée tout en haut, on utilise donc le niveau du haut du TMS
                $topID = $tms->getTopLevel();
            } else {
                # On prend comme niveau du haut le niveau juste en dessous du niveau du bas de la source suivante
                $topID = $tms->getBelowLevelID($orderedSources[$i+1]->getBottomID());
            }
            if (! defined $topID) {
                ERROR(sprintf "Cannot auto detect the top level from image or WMS sources");
                return FALSE;
            }
            DEBUG("Top level auto detection for the source with bottom level $bottomID : $topID");
            $s->setTopID($topID);
        }

        my $topOrder = $tms->getOrderfromID($topID);
        if (! defined $topOrder) {
            ERROR(sprintf "The top level $topID in a source does not exist in the TMS");
            return FALSE;
        }
        $s->setTopOrder($topOrder);

        if ($bottomOrder > $topOrder) {
            ERROR("The bottom level is above the top level for a source ($bottomID > $topID)");
            return FALSE;
        }

        for (my $i = $bottomOrder; $i <= $topOrder; $i++) {
            if (exists $orders{$i}) {
                ERROR("We have overlapping between sources");
                return FALSE;
            }
            $orders{$i} = 1;
        }

        if (! defined $globalTopOrder || $topOrder > $globalTopOrder) {
            $globalTopOrder = $topOrder;
        }

        if (! defined $globalBottomOrder || $bottomOrder < $globalBottomOrder) {
            $globalBottomOrder = $bottomOrder;
        }
    }
    
    ####################### ADD LEVELS TO OUTPUT PYRAMID

    ALWAYS(">>> Add new levels ...");
    foreach my $s (@{$this{loaded}->{sources}}) {
        for (my $order = $s->getBottomOrder(); $order <= $s->getTopOrder(); $order++) {
            
            my $ID = $tms->getIDfromOrder($order);

            if (! $this{loaded}->{output_pyramid}->addLevel($ID) ) {
                ERROR("Cannot add level $ID");
                return FALSE;
            }
        }
    }

    ####################### FOREST
    ALWAYS(">>> Load Forest ...");
  
    $this{loaded}->{forest} = ROK4::PREGENERATION::Forest->new(
        $this{loaded}->{output_pyramid},
        $this{loaded}->{sources},
        $params->{process}
    );

    if (! defined $this{loaded}->{forest}) {
        ERROR("Can not load the forest !");
        return FALSE;
    }

    #######################
    
    ALWAYS(">>> Write the pyramid's list ...");

    if ( ! writeListAndReferences() ) {
        ERROR("Can not write Pyramid list and reference ancestor if exist !");
        return FALSE;
    }
    
    #######################

    ALWAYS(">>> Write the pyramid's descriptor ...");

    if ( ! $this{loaded}->{output_pyramid}->writeDescriptor() ) {
        ERROR("Can not write Pyramid descriptor !");
        return FALSE;
    }
  
    #######################
    # compute graphs
    
    ALWAYS(">>> Compute forest ...");
    
    if (! $this{loaded}->{forest}->computeGraphs()) {
        ERROR("Can not compute forest !");
        return FALSE;
    }

    #######################
    # Écrire le script principal
    ALWAYS(">>> Write main script");
    my $scriptPath = File::Spec->catfile($ROK4::BE4::Shell::SCRIPTSDIR, "main.sh");
    open(MAIN, ">$scriptPath") or do {
        ERROR("Cannot open '$scriptPath' to write in it");
        return FALSE;
    };

    print MAIN ROK4::BE4::Shell::getMainScript($this{loaded}->{output_pyramid});

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
