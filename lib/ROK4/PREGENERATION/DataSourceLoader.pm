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
File: DataSourceLoader.pm

Class: ROK4::PREGENERATION::DataSourceLoader

(see libperlauto/Core_DataSourceLoader.png)

Loads, validates and manages data sources. Data sources informations are read from a specific configuration file.

Using:
    (start code)
    use ROK4::PREGENERATION::DataSourceLoader

    # DataSourceLoader object creation
    my $objDataSourceLoader = ROK4::PREGENERATION::DataSourceLoader->new({
        filepath_conf => "/home/IGN/CONF/source.txt",
    });

    (end code)

Attributes:
    FILEPATH_DATACONF - string - Path to the specific datasources configuration file.
    type - string - Data type of all data source, RASTER or VECTOR  
    dataSources - <ROK4::PREGENERATION::DataSource> array - Data sources ensemble. Can contain just one element.

=cut

################################################################################

package ROK4::PREGENERATION::DataSourceLoader;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;
use List::Util qw(min max);

# My module
use ROK4::Core::Config;
use ROK4::PREGENERATION::DataSource;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################

BEGIN {}
INIT {}
END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

DataSourceLoader constructor. Bless an instance.

Parameters (list):
    datasource - hash - Section *datasource*, in the general BE4 configuration file. Contains the key "filepath_conf"
|               filepath_conf - string - Path to the data sources configuration file
    tms_name - string - TMS name, to determine level order, from the *pyramid* section in the configuration file
    topID - string - Optionnal, from the *pyramid* section in the configuration file

See also:
    <_init>, <_load>
=cut
sub new {
    my $class = shift;
    my $datasource = shift;
    my $tms_name = shift;
    my $topID = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        FILEPATH_DATACONF => undef,
        type => undef,
        dataSources => [],
        topOrder => undef,
        bottomOrder => undef
    };

    bless($this, $class);

    return undef if (! $this->_init($datasource));
    return undef if (! $this->_load());
    return undef if (! $this->_update($tms_name, $topID));
    
    INFO (sprintf "Data sources number : %s",scalar @{$this->{dataSources}});

    return $this;
}

=begin nd
Function: _init

Checks the "datasource" section. Must contain key "filepath_conf" (and path is tested)

Parameters (list):
    datasource - hash - Section *datasource*, in the general BE4 configuration file. Contains the key "filepath_conf" :
|               filepath_conf - string - Path to the data sources configuration file
=cut
sub _init {
    my $this   = shift;
    my $datasource = shift;

    return FALSE if (! defined $datasource);
    
    if (! exists($datasource->{filepath_conf}) || ! defined ($datasource->{filepath_conf})) {
        ERROR("'filepath_conf' is required in the 'datasource' section !");
        return FALSE ;
    }
    if (! -f $datasource->{filepath_conf}) {
        ERROR (sprintf "Data's configuration file ('%s') doesn't exist !",$datasource->{filepath_conf});
        return FALSE;
    }
    $this->{FILEPATH_DATACONF} = $datasource->{filepath_conf};

    return TRUE;
}

=begin nd
Function: _load

Reads the specific data sources configuration file and creates corresponding <COMMON:DataSource> objects.
=cut
sub _load {
    my $this   = shift;


    my $propLoader = ROK4::Core::Config->new($this->{FILEPATH_DATACONF});

    if (! defined $propLoader) {
        ERROR("Can not load sources' properties !");
        return FALSE;
    }

    my %sourcesProperties = $propLoader->getConfigurationCopy();

    if (! scalar keys %sourcesProperties) {
        ERROR("All parameters properties of sources are empty !");
        return FALSE;
    }

    while( my ($level,$params) = each(%sourcesProperties) ) {
        my $datasource = ROK4::PREGENERATION::DataSource->new($level,$params);
        if (! defined $datasource) {
            ERROR(sprintf "Cannot create a DataSource object for the base level %s",$level);
            return FALSE;
        }

        if (defined $this->{type} && $this->{type} ne $datasource->getType()) {
            ERROR("All data sources must have the same type, RASTER or VECTOR");
            return FALSE;
        } else {
            $this->{type} = $datasource->getType();
        }

        if ($datasource->getBottomID() eq "<AUTO>" && ! $datasource->hasImages()) {
            ERROR("Auto detect the bottom level is only possible with image source");
            return FALSE;
        }

        push @{$this->{dataSources}}, $datasource;
    }

    if (scalar(@{$this->{dataSources}}) == 0) {
        ERROR ("No source !");
        return FALSE;
    }

    return TRUE;
}

=begin nd
Function: _update

From data sources, TMS and parameters, we identify top and bottom :
    - bottom level = the lowest level among data source base levels
    - top level = levelID in parameters if defined, top level of TMS otherwise.

For each datasource, we store the order and the ID of the higher level which use this datasource.
The base level (from which datasource is used) can be determined if the datasource owns a image source.

Example (with 2 data sources) :
    - DataSource1: from level-18 (order 2) to level-16 (order 4)
    - DataSource1: from level-15 (order 5) to level-12 (order 8)

There are no superposition between data sources.

Parameters:
    tms_name - string - TMS name, to determine level order, from the *pyramid* section in the configuration file
    topID - string - Optionnal, from the *pyramid* section in the configuration file
    
Returns TRUE if success, FALSE if failure
=cut
sub _update {
    my $this = shift;
    my $tms_name = shift;
    my $topID = shift;

    my $tms = ROK4::Core::TileMatrixSet->new($tms_name);
    if (! defined $tms) {
        ERROR(sprintf "Cannot create a TileMatrixSet object from the TMS name %s", $tms_name);
        return FALSE;
    }
    
    ######## DETERMINE GLOBAL TOP/BOTTOM LEVELS ########
    
    # Définition du topLevel :
    #  - En priorité celui fourni en paramètre
    #  - Par defaut, c'est le plus haut niveau du TMS,
    if (defined $topID) {
        $this->{topOrder} = $tms->getOrderfromID($topID);
        if (! defined $this->{topOrder}) {
            ERROR(sprintf "The top level defined in configuration ('%s') does not exist in the TMS !",$topID);
            return FALSE;
        }
    } else {
        $topID = $tms->getTopLevel();
        $this->{topOrder} = $tms->getOrderfromID($topID);
    }

    # Définition du bottomLevel :
    #  - celui fournit dans la configuration des sources : le niveau le plus bas de toutes les sources
    # En plus :
    #  - on vérifie la cohérence des niveaux défini dans la configuration des sources avec le niveau du haut
    #  - on renseigne l'ordre du niveau du bas pour chaque source de données
    my $bottomID = undef;    
    foreach my $datasource (@{$this->{dataSources}}) {
        my $dsBottomID = $datasource->getBottomID();

        if ($dsBottomID eq "<AUTO>") {
            INFO("Bottom level auto detection for an image source...");
            $dsBottomID = $tms->getBestLevelID($datasource->getImageSource()->getBestResImage());
            if (! defined $dsBottomID) {
                ERROR(sprintf "Cannot auto detect the bottom level from image source best resolution");
                return FALSE;
            }
            $datasource->setBottomID($dsBottomID);
        }

        my $dsBottomOrder = $tms->getOrderfromID($dsBottomID);
        if (! defined $dsBottomOrder) {
            ERROR(sprintf "The level present in source configuration ('%s') does not exist in the TMS !", $dsBottomID);
            return FALSE;
        }

        if ($this->{topOrder} < $dsBottomOrder) {
            ERROR(sprintf "A level in sources configuration (%s) is higher than the top level defined in the be4 configuration (%s).",$dsBottomID,$topID);
            return FALSE;
        }
        
        $datasource->setBottomOrder($dsBottomOrder);
        
        if (! defined $this->{bottomOrder} || $dsBottomOrder < $this->{bottomOrder}) {
            $bottomID = $dsBottomID;
            $this->{bottomOrder} = $dsBottomOrder;
        }
    }

    if ($this->{topOrder} == $this->{bottomOrder}) {
        INFO(sprintf "Top and bottom levels are identical (%s) : just one level will be generated",$bottomID);
    }
    
    ######## DETERMINE FOR EACH DATASOURCE TOP/BOTTOM LEVELS ########
    
    @{$this->{dataSources}} = sort {$a->getBottomOrder() <=> $b->getBottomOrder()} ( @{$this->{dataSources}});
    
    for (my $i = 0; $i < scalar @{$this->{dataSources}} - 1; $i++) {
        my $dsTopOrder = $this->{dataSources}[$i+1]->getBottomOrder() - 1;
        $this->{dataSources}[$i]->setTopOrder($dsTopOrder);
        $this->{dataSources}[$i]->setTopID($tms->getIDfromOrder($dsTopOrder));
    }
    
    $this->{dataSources}[-1]->setTopID($topID);
    $this->{dataSources}[-1]->setTopOrder($this->{topOrder});
    
    if ($this->{topOrder} < $this->{bottomOrder}) {
        ERROR(sprintf "Pas bon ça : c'est sens dessus dessous (%s - %s < %s - %s)", $this->{topOrder}, $topID, $this->{bottomOrder}, $bottomID);
        ERROR("Et ça, ça c'est pas normal !");
        return FALSE;
    }
    
    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getType
sub getType {
    my $this = shift;
    return $this->{type}; 
}

# Function: getExtremOrders
sub getExtremOrders {
    my $this = shift;
    return ($this->{bottomOrder}, $this->{topOrder});
}

# Function: getDataSources
sub getDataSources {
    my $this = shift;
    return $this->{dataSources}; 
}

# Function: getDataSource
sub getDataSource {
    my $this = shift;
    my $order = shift;


    foreach my $datasource (@{$this->{dataSources}}) {
        if ($order >= $datasource->getBottomOrder() && $order <= $datasource->getTopOrder()) {
            return $datasource;
        }
    }

    return undef; 
}

# Function: getNumberDataSources
sub getNumberDataSources {
    my $this = shift;
    return scalar @{$this->{dataSources}}; 
}

=begin nd
Function: getPixelFromSources

Store pixel informations extracted from sources into pyramid parameters

Parameters:
    params - hash reference - Pyramid section from configuration
=cut
sub getPixelFromSources {
    my $this = shift;
    my $params = shift;

    if ($this->{type} ne "RASTER") {
        ERROR("Pixel specifications cannot be extract from not RASTER sources");
        return FALSE;
    }

    my $pixel = undef;
    foreach my $source (@{$this->{dataSources}}) {
        if (! $source->hasImages()) {next;}

        my $pix = $source->getPixel();

        if (! defined $pixel) {
            $pixel = $pix;
            next;
        }

        if (! $pix->equals($pixel)) {
            ERROR("We have several images sources but pixel caracteristics are different, we can't extract ONE format from sources for output");
            return FALSE;
        }
    }

    if (defined $pixel) {
        if ( ! exists $params->{photometric} || 
             ! exists $params->{sampleformat} || 
             ! exists $params->{bitspersample} || 
             ! exists $params->{samplesperpixel} ) {

            INFO(
                "One pixel parameter is missing (photometric, sampleformat, bitspersample or samplesperpixel), we pick all information from image source"
            );

            $params->{samplesperpixel} = $pixel->getSamplesPerPixel();
            $params->{sampleformat} = $pixel->getSampleFormat();
            $params->{photometric} = $pixel->getPhotometric();
            $params->{bitspersample} = $pixel->getBitsPerSample();
        }
    }

    return TRUE;
}

####################################################################################################
#                                Group: Export methods                                             #
####################################################################################################

=begin nd
Function: exportForDebug

Returns all informations about the data sources loader. Useful for debug.

Example:
    (start code)
    (end code)
=cut
sub exportForDebug {
    my $this = shift ;
    
    my $export = "";
    
    $export .= sprintf "\n Object ROK4::PREGENERATION::DataSourceLoader :\n";
    $export .= sprintf "\t Configuration file : %s\n", $this->{FILEPATH_DATACONF};
    $export .= sprintf "\t Sources type : %s\n", $this->{type};
    $export .= sprintf "\t Sources number : %s\n", scalar @{$this->{dataSources}};
    
    return $export;
}

1;
__END__

=begin nd

Group: details

Configuration file examples (WMS harvesting).

_In the be4 configuration, section *datasource* (multidata.conf)_
    (start code)
    [ datasource ]
    filepath_conf       = /home/IGN/CONF/source.txt
    (end code)

_In the source configuration (source.txt)_
    (start code)
    [ 19 ]
    
    srs                 = IGNF:LAMB93
    path_image          = /home/theo/DONNEES/BDORTHO_PARIS-OUEST_2011_L93/DATA
    
    wms_layer   = ORTHO_RAW_LAMB93_PARIS_OUEST
    wms_url     = http://localhost/wmts/rok4
    wms_version = 1.3.0
    wms_request = getMap
    wms_format  = image/tiff
    max_width = 2048
    max_height = 2048
    
    [ 14 ]
    
    srs = IGNF:WGS84G
    extent = /home/IGN/SHAPE/Polygon.txt
    
    wms_layer   = ORTHO_RAW_LAMB93_D075-O
    wms_url     = http://localhost/wmts/rok4
    wms_version = 1.3.0
    wms_request = getMap
    wms_format  = image/tiff
    max_width = 4096
    max_height = 4096
    (end code)
    
=cut
