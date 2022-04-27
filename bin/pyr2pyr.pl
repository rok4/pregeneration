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
File: pyr2pyr.pl
=cut

################################################################################

use warnings;
use strict;

use POSIX qw(locale_h);

# Module
use Log::Log4perl qw(:easy);
use Getopt::Long;
use File::Basename;
use File::Path;
use Cwd;
use Data::Dumper;


# My search module
use FindBin qw($Bin);
use lib "$Bin/../lib/perl5";

# My home-made modules
use ROK4::Core::Base36;

use ROK4::PYR2PYR::Validator;
use ROK4::PYR2PYR::Shell;

use ROK4::Core::PyramidRaster;
use ROK4::Core::PyramidVector;
use ROK4::Core::ProxyPyramid;
use ROK4::PREGENERATION::Script;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################
# Version
my $VERSION = '@VERSION@';


my %options =
(
    "version"    => 0,
    "help"       => 0,
    "usage"      => 0,

    # Configuration
    "properties"  => undef, # file properties params (mandatory) !
);

=begin nd
Variable: HANDLEDCONVERSION

Define handled storage type conversion : if $HANDLEDCONVERSION{fromStorageType}->{toStorageType} exists, it's handled
=cut
my %HANDLEDCONVERSION = (
    "FILE" => {
        "CEPH" => 1,
        "FILE" => 1,
        "S3" => 1,
        "SWIFT" => 1
    },
    "CEPH" => {
        "CEPH" => 1,
        "FILE" => 1,
        "S3" => 1,
        "SWIFT" => 1
    },
    "S3" => {
        "FILE" => 1
    }
);

=begin nd
Variable: this

All parameters by section
=cut
my %this = (
    params => undef,
    loaded => {
        input_pyramid => undef,
        output_pyramid => undef
    }
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
        my $message = "ERROR CONFIGURATION !";
        printf STDERR "%s\n", $message;
        exit 2;
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

####################################################################################################
#                                 Group: Process methods                                           #
####################################################################################################

=begin nd
Function: config

Loads properties files and validate using <ROK4::PYR2PYR::Validator::validate>.
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
    
    if (! ROK4::PYR2PYR::Validator::validate($this{params})) {
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

sub doIt {

    ############################## LA PYRAMIDE EN ENTRÉE

    $this{loaded}->{input_pyramid} = ROK4::Core::ProxyPyramid::load($this{params}->{from}->{descriptor});

    if (! defined $this{loaded}->{input_pyramid}) {
        ERROR("Cannot load the source Pyramid object (neither raster nor vector)");
        return FALSE;
    }

    ############################## LA PYRAMIDE EN SORTIE

    # On part d'un clone de la pyramide en entrée, en changeant le nom puis le stockage
    $this{loaded}->{output_pyramid} = $this{loaded}->{input_pyramid}->clone($this{params}->{to}->{name});
    $this{loaded}->{output_pyramid}->updateStorageInfos($this{params}->{to}->{storage});

    ############################## LA CONVERSION EST ELLE GÉRÉE


    if (! exists $HANDLEDCONVERSION{$this{loaded}->{input_pyramid}->getStorageType()}->{$this{loaded}->{output_pyramid}->getStorageType()}) {
        ERROR(sprintf "PYR2PYR %s -> %s not available", $this{loaded}->{input_pyramid}->getStorageType(), $this{loaded}->{output_pyramid}->getStorageType());
        return FALSE;
    }

    if (! $this{loaded}->{output_pyramid}->writeDescriptor()) {
        ERROR("Cannot write output pyramid descriptor");
        return FALSE;
    }

    ############################## LES COMMANDES SHELL

    if (! ROK4::PYR2PYR::Shell::setGlobals($this{params}->{process})) {
        ERROR ("Impossible d'initialiser la librairie des commandes Shell pour PYR2PYR");
        return FALSE;
    }
    my $scriptInit = ROK4::PYR2PYR::Shell::getScriptInitialization($this{loaded}->{input_pyramid}, $this{loaded}->{output_pyramid});

    my $follow_links = FALSE;
    if (defined $this{params}->{process}->{follow_links} && $this{params}->{process}->{follow_links}) {
        $follow_links = TRUE;
    }

    ############################## LES SCRIPTS

    my @scripts;
    my $scriptInd = 0;
    for (my $i = 1 ; $i <= $this{params}->{process}->{parallelization}; $i++) {

        my $s = ROK4::PREGENERATION::Script->new({
            id => "SCRIPT_$i",
            finisher => FALSE,
            shellClass => 'ROK4::PYR2PYR::Shell',
            initialisation => $scriptInit
        });

        if (! defined $s) {
            ERROR("Can not create the script $i");
            return FALSE;
        }

        push(@scripts, $s);
    }

    my $s = ROK4::PREGENERATION::Script->new({
        id => "SCRIPT_FINISHER",
        finisher => TRUE,
        shellClass => 'ROK4::PYR2PYR::Shell',
        initialisation => $scriptInit
    });

    if (! defined $s) {
        ERROR("Can not create the script finisher");
        return FALSE;
    }

    push(@scripts, $s);


    ############################## TRAITEMENT DES DALLES

    if (! $this{loaded}->{input_pyramid}->loadList()) {
        ERROR("Cannot cache content list of the source pyramid");
        return FALSE;
    }

    my $slabs = $this{loaded}->{input_pyramid}->getLevelsSlabs();

    ### Calcul du nombre d'image à traiter
    my $total = 0;
    foreach my $level (keys(%{$slabs})) {
        $total += scalar(values(%{$slabs->{$level}->{DATA}}));
        $total += scalar(values(%{$slabs->{$level}->{MASK}}));
    }

    INFO("$total slab(s) to process");

    my $totalImagesPerScript = int($total/$this{params}->{process}->{parallelization});
    INFO("$totalImagesPerScript slab(s) per script to process");

    my $dataRootFrom = $this{loaded}->{input_pyramid}->getDataRoot();
    my $storageTypeFrom = $this{loaded}->{input_pyramid}->getStorageType();
    foreach my $type ("DATA", "MASK") {
        foreach my $level (keys(%{$slabs})) {
            while( my ($key, $parts) = each(%{$slabs->{$level}->{$type}}) ) {

                if (! $follow_links && $parts->{root} ne $dataRootFrom) {
                    # C'est un lien symbolique dans la pyramide et nous n'en voulons pas
                    next;
                }

                # On veut s'assurer que input soit une vraie dalle, pas un lien symbolique.
                # Autant ce n'est pas grave dans le cas d'un stockage fichier puisque le lien sera parcouru automatiquement
                # Dans le cas d'un stockage objet, si on recopie l'objet symbolique au lieu de la cible, on perdra la donnée

                # De plus, dans le cas d'un stockage objet, la racine dans le fichier liste contient le contenant et le préfixe
                # Le contenant doit rester à part, car il intervient dans une autre option dans les commandes
                # Mais on doit mettre le préfixe dans input

                # Donc dans le cas fichier on va mettre en input le chemin complet vers la vraie dalle (on évite un rebond sur un lien symbolique)
                # Dans le cas objet on va mettre en input le nom complet de l'objet (sans le contenant)

                my ($col,$row) = split("_", $key);
                my $input;
                if ($storageTypeFrom eq "FILE") {
                    $input = $parts->{origin};
                } else {
                    my @p = split("/", $parts->{origin});
                    shift(@p); # On retire le nom du contenant de la racine
                    $input = sprintf "%s/%s", join("/", @p);
                }

                my $output = $this{loaded}->{output_pyramid}->getSlabPath($type, $level, $col, $row, FALSE);

                $scripts[$scriptInd]->write(sprintf "ProcessSlab $input $output\n");
                $scriptInd = ($scriptInd + 1) % $this{params}->{process}->{parallelization};
            }
        }
    }

    ############################## ÉCRITURE DE L'EN TÊTE DE LISTE DANS LE FINISHER

    my $root = $this{loaded}->{output_pyramid}->getDataRoot();
    $scripts[-1]->write("echo '0=$root\n#' >\${LIST_FILE}\n");

    ############################## FERMETURE DES SCRIPTS

    foreach my $s (@scripts) {
        $s->close();
    }

    ############################## SCRIPT PRINCIPAL

    ALWAYS(">>> Write main script");
    my $scriptPath = File::Spec->catfile($ROK4::PYR2PYR::Shell::SCRIPTSDIR, "main.sh");
    open(MAIN, ">$scriptPath") or do {
        ERROR("Cannot open '$scriptPath' to write in it");
        return FALSE;
    };

    print MAIN ROK4::PYR2PYR::Shell::getMainScript();

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
