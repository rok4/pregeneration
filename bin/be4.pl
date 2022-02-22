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
use ROK4::BE4::PropertiesLoader;
use ROK4::Core::PyramidRaster;
use ROK4::Core::DataSourceLoader;
use ROK4::Core::Forest;
use ROK4::Core::Array;
use ROK4::Core::CheckUtils;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

my %UPDATESMODES = (
    "FILE" => ["slink", "hlink", "copy", "inject" ],
    "S3" => ["slink", "copy", "inject" ],
    "SWIFT" => ["slink", "copy", "inject" ],
    "CEPH" => ["slink", "copy", "inject" ]
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
    environment - Environment file
=cut
my %options =
(
    "version"    => 0,
    "help"       => 0,
    "usage"      => 0,
    
    # Configuration
    "properties"  => undef, # file properties params (mandatory) !
    "environment" => undef  # file environment be4 params (optional) !
);

=begin nd
Variable: this

All parameters by section :

    logger - Can be null
    datasource - 
    pyramid -
    process - 
=cut
my %this =
(
    params => {
        logger        => undef,
        datasource    => undef,
        pyramid       => undef,
        process       => undef
    },
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

Checks options and initializes the default logger. Check environment file (optionnal) and properties file (mandatory).
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
            printf "See documentation here: https://github.com/rok4/rok4\n" ;
            exit 0;
        },
        "version|v" => sub { exit 0; },
        "usage" => sub {
            printf "See documentation here: https://github.com/rok4/rok4\n" ;
            exit 0;
        },
        
        "properties|conf=s" => \$options{properties},
        "environment|env=s" => \$options{environment}
    ) or do {
        printf "Unappropriate usage\n";
        printf "See documentation here: https://github.com/rok4/rok4\n";
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
    
    # env : optional !
    if (defined $options{environment} && $options{environment} ne "") {
        my $fenvironment = File::Spec->rel2abs($options{environment});
        $options{environment} = $fenvironment;
    }
    
    return TRUE;
}

=begin nd
Function: config

Loads environment and properties files and merge parameters. Those in the properties file have priority over those in the environment file.

See Also:
    <checkParams>
=cut
sub config {

    ###################
    ALWAYS(">>> Load Properties ...");
    
    my $fprop = $options{properties};
    my $objProp = ROK4::BE4::PropertiesLoader->new($fprop);
    
    if (! defined $objProp) {
        ERROR("Can not load specific properties !");
        return FALSE;
    }
    
    my %props = $objProp->getAllProperties();
    
    if (! scalar keys %props) {
        ERROR("All parameters properties are empty !");
        return FALSE;
    }

    ###################

    my $hashref;

    ###################
    ALWAYS(">>> Treat optionnal environment ...");

    my $fenv = undef;
    $fenv = $options{environment} if (defined $options{environment} && $options{environment} ne "");

    if (defined $fenv) {
        my $objEnv = ROK4::Core::Config->new($fenv);

        if (! defined $objEnv) {
            ERROR("Can not load environment properties !");
            return FALSE;
        }

        my %envs = $objEnv->getConfigurationCopy();

        if (! scalar keys %envs) {
            ERROR("All parameters environment are empty !");
            return FALSE;
        }
        
        foreach (keys %{$this{params}}) {
            my $href = { map %$_, grep ref $_ eq 'HASH', ($envs{$_}, $props{$_}) };
            $hashref->{$_} = $href;
        }
    } else {
        foreach (keys %{$this{params}}) {
            my $href = { map %$_, grep ref $_ eq 'HASH', ($props{$_}) };
            $hashref->{$_} = $href;
        }
    }

    ###################

    if (! defined $hashref) {
        ERROR("Can not merge all parameters of properties !");
        return FALSE;
    }
  
    # save params properties
    $this{params} = $hashref;
    
    ###################
    # check parameters
    
    my $pyramid     = $this{params}->{pyramid};       #
    my $logger      = $this{params}->{logger};        # 
    my $datasource  = $this{params}->{datasource};    #
    my $process     = $this{params}->{process};       # 
    
    # pyramid
    if (! defined $pyramid) {
        ERROR("Parameters Pyramid can not be null !");
        return FALSE;
    }
    
    # datasource
    if (! defined $datasource) {
        ERROR("Parameters Datasource can not be null !");
        return FALSE;
    }
    
    # process
    if (! defined $process) {
        ERROR("Parameters Process can not be null !");
        return FALSE;
    }
    
    # logger
    if (defined $logger) {
    
        my @args;
        
        my $layout= '%5p : %m (%M) %n';
        my $level = $logger->{log_level};
        my $out   = sprintf (">>%s", File::Spec->catfile($logger->{log_path}, $logger->{log_file}))
            if (! ROK4::Core::CheckUtils::isEmpty($logger->{log_path}) && ! ROK4::Core::CheckUtils::isEmpty($logger->{log_file}));
        
        $out   = "STDOUT" if (! defined $out);
        $level = "WARN" if (! defined $level);
        
        if ($level =~ /(ALL|DEBUG)/) {
            $layout = '%5p : %m (%M) %n';
        }
        
        # add the param logger by default (user settings !)
        push @args, {
            file   => $out,
            level  => $level,
            layout => $layout,
        };
        
        if ($out ne "STDOUT") {
            # add the param logger to the STDOUT
            push @args, {
                file   => "STDOUT",
                level  => $level,
                layout => $layout,
            },
        }
        Log::Log4perl->easy_init(@args);
    }
    
    
    return TRUE;
}

=begin nd
Function: writeListAndReferences
=cut
sub writeListAndReferences {
    my $forest = shift;
    my $newpyr = shift;
    my $ancestor = shift;
    my $commonTempDir = shift;

    my $updateMode = $this{params}->{pyramid}->{update_mode};
    my $storageType = $newpyr->getStorageType();

    if ($newpyr->{type} eq "READ") {
        ERROR("Cannot write list of 'read' pyramid");
        return FALSE;        
    }

    if (defined $ancestor && ref ($ancestor) ne "ROK4::Core::PyramidRaster" ) {
        ERROR(sprintf "Ancestor, if provided, have to be a ROK4::Core::PyramidRaster ! ");
        return FALSE;
    }

    my $newListPath = "$commonTempDir/content.list";
    
    my $newRoot = $newpyr->getDataRoot();

    my $NEWLIST;

    if (! open $NEWLIST, ">", $newListPath) {
        ERROR(sprintf "Cannot open new pyramid list file (write) : %s",$newListPath);
        return FALSE;
    }
    
    if (! defined $ancestor) {
        # Pas d'ancêtre, on doit juste écrire l'en tête : le dossier propre à cette pyramide ou le nom du conteneur objet
        print $NEWLIST "0=$newRoot\n";
        print $NEWLIST "#\n";
        close $NEWLIST;
        return TRUE
    }

    ############################## RÉFÉRENCEMENT DES FICHIERS DE L'ANCÊTRE #######################################

    # On a un ancêtre, il va falloir en référencer toutes les dalles

    if (! defined $forest || ref ($forest) ne "ROK4::Core::Forest" ) {
        ERROR(sprintf "We need a ROK4::Core::Forest to write pyramid list ! ");
        return FALSE;
    }

    # On va lire la liste de l'ancêtre
    if (! $ancestor->loadList()) {
        ERROR("Cannot cache content list of the ancestor pyramid");
        return FALSE;
    }

    my $slabs = $ancestor->getLevelsSlabs();
    my $rootsNumber = 1;
    my %roots = (
        $newRoot => 0
    );

    while( my ($level, $levelSlabs) = each(%{$slabs}) ) {
        if (! defined $newpyr->getLevel($level)) {
            # La dalle appartient à un niveau qui n'est pas voulu dans la nouvelle pyramide
            next;
        }

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

            if (! $forest->containsNode($level,$col,$row)) {

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

        if ($newpyr->ownMasks()) {
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

                if (! $forest->containsNode($level,$col,$row)) {

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

Steps in order, using parameters :
    - load ancestor pryamid if exists : <ROK4::Core::PyramidRaster::new>
    - load data sources : <ROK4::Core::DataSourceLoader::new>
    - create the Pyramid object : <ROK4::Core::PyramidRaster::new>
    - update the Pyramid object with the TMS : <ROK4::Core::PyramidRaster::bindTileMatrixSet>
    - update data sources with the levels : <ROK4::Core::DataSourceLoader::updateDataSources>
    - create the pyramid's levels : <ROK4::Core::PyramidRaster::addLevel>
    - create the Forest object : <ROK4::Core::Forest::new>
    - write the pyramid's list : <writeListAndReferences>
    - write the pyramid's descriptor : <ROK4::Core::PyramidRaster::writeDescriptor>
    - compute trees (write scripts) : <ROK4::Core::Forest::computeGraphs>
=cut
sub doIt {

    #######################
    # link to parameters
    my $params = $this{params};
    
    #######################
    # objects to implemented
    
    my $objAncestorPyramid = undef;
    my $objPyramid = undef;
    my $objDSL = undef;
    my $objForest = undef;

    #######################
    # if ancestor, read it

    if (exists $params->{pyramid}->{update_pyr} && defined $params->{pyramid}->{update_pyr}) {
    
        ALWAYS(">>> Load the pyramid to update ...");

        my $ancestorDescriptor = $params->{pyramid}->{update_pyr};
        $objAncestorPyramid = ROK4::Core::PyramidRaster->new("DESCRIPTOR", $ancestorDescriptor );
        if (! defined $objAncestorPyramid) {
            ERROR("Cannot load ancestor pyramid !");
            return FALSE;
        }
        my $ancestorStorageType = $objAncestorPyramid->getStorageType();

        if (! defined $params->{pyramid}->{update_mode} || $params->{pyramid}->{update_mode} eq "") {
            ERROR("If we want to update a pyramid, we need the 'update_mode' parameter");
            return FALSE;
        }

        my $updateMode = $params->{pyramid}->{update_mode} ;
        if (! defined ROK4::Core::Array::isInArray($updateMode, @{$UPDATESMODES{$ancestorStorageType}}) ) {
            ERROR("Update mode '$updateMode' is not allowed for $ancestorStorageType pyramids");
            return FALSE;
        }

        if (! $objAncestorPyramid->bindTileMatrixSet($params->{pyramid}->{tms_path})) {
            ERROR("Cannot bind TMS to ancestor pyramid !");
            return FALSE;
        }

        # Dans le cas de l'injection, on veut que la nouvelle pyramide soit écrite sur l'ancienne
        # On va donc modifier le nom et les emplacements pour mettre les mêmes que ceux de l'ancêtre
        # On s'assure également de la compatibilité du stockage

        if ($updateMode eq "inject") {
            WARN("'inject' update mode is selected, ancestor is modified, without possible rollback.");
            if ($ancestorStorageType eq "FILE") {
                $params->{pyramid}->{pyr_data_path} = $objAncestorPyramid->getStorageRoot();
                $params->{pyramid}->{pyr_data_pool_name} = undef;
                $params->{pyramid}->{pyr_data_bucket_name} = undef;
                $params->{pyramid}->{pyr_data_container_name} = undef;
            }
            elsif ($ancestorStorageType eq "CEPH") {
                $params->{pyramid}->{pyr_data_pool_name} = $objAncestorPyramid->getStorageRoot();
                $params->{pyramid}->{pyr_data_container_name} = undef;
                $params->{pyramid}->{pyr_data_bucket_name} = undef;
                $params->{pyramid}->{pyr_data_path} = undef;
            }
            elsif ($ancestorStorageType eq "S3") {
                $params->{pyramid}->{pyr_data_bucket_name} = $objAncestorPyramid->getStorageRoot();
                $params->{pyramid}->{pyr_data_pool_name} = undef;
                $params->{pyramid}->{pyr_data_container_name} = undef;
                $params->{pyramid}->{pyr_data_path} = undef;
            }
            elsif ($ancestorStorageType eq "SWIFT") {
                $params->{pyramid}->{pyr_data_container_name} = $objAncestorPyramid->getStorageRoot();
                $params->{pyramid}->{pyr_data_pool_name} = undef;
                $params->{pyramid}->{pyr_data_bucket_name} = undef;
                $params->{pyramid}->{pyr_data_path} = undef;
            }
            $params->{pyramid}->{pyr_name_new} = $objAncestorPyramid->getName();
        }
    }
    
    #######################
    # load data source
    
    ALWAYS(">>> Load Data Source ...");

    $objDSL = ROK4::Core::DataSourceLoader->new($params->{datasource});
    if (! defined $objDSL) {
        ERROR("Cannot load data sources !");
        return FALSE;
    }

    if ($objDSL->getType() ne "RASTER") {
        ERROR("BE4 expect RASTER data sources !");
        return FALSE;
    }
    
    my ($ok, $pixelIn) = $objDSL->getPixelFromSources();
    if (! $ok) {
        ERROR("Cannot extract ONE pixel information from sources");
        return FALSE;
    }

    #######################
    # create a pyramid
    
    ALWAYS(">>> Load the new pyramid ...");
    
    $objPyramid = ROK4::Core::PyramidRaster->new("VALUES", $params->{pyramid}, $objAncestorPyramid, $pixelIn );
    if (! defined $objPyramid) {
        ERROR("Cannot create output Pyramid !");
        return FALSE;
    }

    if (defined $objAncestorPyramid && $objAncestorPyramid->getStorageType ne $objPyramid->getStorageType()) {
        ERROR("New pyramid and ancestor have to own the same storage type");
        ERROR("Ancestor = ".$objAncestorPyramid->getStorageType);
        ERROR("New = ".$objPyramid->getStorageType);
        return FALSE;
    }

    # Environment variables nécessaire au stockage

    if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables($objPyramid->getStorageType())) {
        ERROR(sprintf "Environment variable is missing for a %s storage", $objPyramid->getStorageType());
        return FALSE;
    }

    if (! $objPyramid->bindTileMatrixSet($params->{pyramid}->{tms_path})) {
        ERROR("Cannot bind TMS to output Pyramid !");
        return FALSE;
    }

    my $objTMS = $objPyramid->getTileMatrixSet();

    # update datasources top/bottom levels !
    my ($bottomOrder,$topOrder) = $objDSL->updateDataSources($objTMS, $params->{pyramid}->{pyr_level_top});
    if ($bottomOrder == -1) {
        ERROR("Cannot determine top and bottom levels, from data sources.");
        return FALSE;
    }
    
    #######################
    # add levels to pyramid
    
    ALWAYS(">>> Determine levels ...");
    
    # Create all level between the bottom and the top
    for (my $order = $bottomOrder; $order <= $topOrder; $order++) {

        my $ID = $objTMS->getIDfromOrder($order);
        if (! defined $ID) {
            ERROR(sprintf "Cannot identify ID for the order %s !", $order);
            return FALSE;
        }

        if (! $objPyramid->addLevel($ID, $objAncestorPyramid) ) {
            ERROR("Cannot add level $ID");
            return FALSE;            
        }
    }
    
    # we cannot write the pyramid descriptor and cache now. We need data's limits, calculated by graphs.
  
    #######################
    # create forest : load graphs
    
    ALWAYS(">>> Load Forest ...");
  
    $objForest = ROK4::Core::Forest->new(
        $objPyramid,
        $objDSL,
        $params->{process}
    );
  
    if (! defined $objForest) {
        ERROR("Can not load the forest !");
        return FALSE;
    }

    #######################
    # write the pyramid list
    
    ALWAYS(">>> Write the pyramid's list ...");

    if ( ! writeListAndReferences($objForest, $objPyramid, $objAncestorPyramid, $params->{process}->{path_temp_common}) ) {
        ERROR("Can not write Pyramid list and reference ancestor if exist !");
        return FALSE;
    }
    
    #######################
    # write the pyramid descriptor

    ALWAYS(">>> Write the pyramid's descriptor ...");

    if ( ! $objPyramid->writeDescriptor() ) {
        ERROR("Can not write Pyramid descriptor !");
        return FALSE;
    }
  
    #######################
    # compute graphs
    
    ALWAYS(">>> Compute forest ...");
    
    if (! $objForest->computeGraphs()) {
        ERROR("Can not compute forest !");
        return FALSE;
    }
    
    DEBUG(sprintf "FOREST (debug export) = %s", $objForest->exportForDebug);

    #######################
    # Écrire le script principal
    ALWAYS(">>> Write main script");
    my $scriptPath = File::Spec->catfile($params->{process}->{path_shell}, "main.sh");
    open(MAIN, ">$scriptPath") or do {
        ERROR("Cannot open '$scriptPath' to write in it");
        return FALSE;
    };

    print MAIN ROK4::BE4::Shell::getMainScript($objPyramid);

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
