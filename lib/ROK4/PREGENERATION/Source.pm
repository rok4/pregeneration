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
File: DataSource.pm

Class: ROK4::PREGENERATION::Source

(see libperlauto/ROK4_Core_DataSource.png)

Manage a data source, physical (image files) or virtual (WMS server) or both.

Using:
    (start code)
    use ROK4::PREGENERATION::Source;
    (end code)

Attributes:
    type - string - Source type : VECTORS, IMAGES, WMS, POSTGRESQL por PYRAMIDS

    bottomID - string - Level identifiant, from which data source is used (base level).
    bottomOrder - integer - Level order, from which data source is used (base level).
    topID - string - Level identifiant, to which data source is used.
    topOrder - integer - Level order, to which data source is used.

    srs - string - SRS of the bottom extent (and SourceImage objects if exists).
    extent - <OGR::Geometry> - Precise extent, in the previous SRS (can be a bbox). It is calculated from the <SourceImage> or supplied in configuration file. 'extent' is mandatory (a bbox or a file which contains a WKT geometry) if there are no images. We have to know area to harvest. If images, extent is calculated thanks data.
    list - string - File path, containing a list of image indices (I,J) to harvest.
    bbox - double array - Data source bounding box, in the previous SRS : [xmin,ymin,xmax,ymax].
    area - string - Provided area : BBOX, LIST or EXTENT

    images - <ROK4::PREGENERATION::SourceImage> - Georeferenced images' source.
    vectors - <ROK4::PREGENERATION::SourceVector> - Vector files source.
    wms - <ROK4::PREGENERATION::SourceWMS> - WMS server.
    database - <ROK4::PREGENERATION::SourceDatabase> - PostgreSQL server.
    pyramids - <ROK4::PREGENERATION::SourcePyramid> - Pyramids source.
    generator_name - string - name of tile generator, for vector sources
    generator_options - string - options for generator calls, for vector sources
=cut

################################################################################

package ROK4::PREGENERATION::Source;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;
use List::Util qw(min max);

# My module
use ROK4::PREGENERATION::SourceImage;
use ROK4::PREGENERATION::SourceWMS;
use ROK4::PREGENERATION::SourceVector;
use ROK4::PREGENERATION::SourceDatabase;
use ROK4::PREGENERATION::SourcePyramid;
use ROK4::Core::PyramidRaster;
use ROK4::Core::ProxyGDAL;


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

DataSource constructor. Bless an instance.

Parameters (list):
    params - hash - Data source parameters (see <_load> for details).

See also:
    <_load>
=cut
sub new {
    my $class = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above) and pod documentation (bottom)
    my $this = {
        type => undef,
        
        bottomID => undef,
        bottomOrder => undef,
        topID => undef,
        topOrder => undef,

        bbox => undef,
        list => undef,
        extent => undef,
        area => undef,

        srs => undef,

        images => undef,
        vectors => undef,
        wms => undef,
        database => undef,
        pyramids => undef,

        generator_name => "",
        generator_options => ""
    };

    bless($this, $class);

    # load. class
    return undef if (! $this->_load($params));

    return $this;
}

=begin nd
Function: _load

Sorts parameters, relays to concerned constructors and stores results.
=cut
sub _load {
    my $this   = shift;
    my $params = shift;
    
    $this->{bottomID} = $params->{bottom};
    $this->{topID} = $params->{top};

    $this->{type} = $params->{source}->{type};

    my $bbox_data = undef;
    if ($this->{type} eq "IMAGES") {
        $this->{images} = ROK4::PREGENERATION::SourceImage->new($params->{source});
        if (! defined $this->{images}) {
            ERROR("Cannot load a IMAGES source");
            return FALSE;
        }
        $this->{srs} = $params->{source}->{srs};
        my @BBOX = $this->{images}->computeBBox();
        $this->{bbox} = \@BBOX;
        $this->{area} = "BBOX";
    }
    elsif ($this->{type} eq "VECTORS") {
        $this->{vectors} = ROK4::PREGENERATION::SourceVector->new($params->{source});
        if (! defined $this->{vectors}) {
            ERROR("Cannot load a VECTORS source");
            return FALSE;
        }
        $this->{srs} = $params->{source}->{srs};
        my @BBOX = $this->{vectors}->computeBBox();
        $this->{bbox} = \@BBOX;
        $this->{area} = "BBOX";

        $this->{generator_name} = "TIPPECANOE";
        if (exists($params->{generator}->{options}) && defined $params->{generator}->{options}) {
            $this->{generator_options} = $params->{generator}->{options};
        }
    }
    elsif ($this->{type} eq "WMS") {
        $this->{wms} = ROK4::PREGENERATION::SourceWMS->new($params->{source});
        if (! defined $this->{wms}) {
            ERROR("Cannot load a WMS source");
            return FALSE;
        }
        if (exists $params->{source}->{area}->{srs}) {
            $this->{srs} = $params->{source}->{area}->{srs};
        }
        if (exists $params->{source}->{area}->{bbox}) {
            $this->{bbox} = $params->{source}->{area}->{bbox};
            $this->{area} = "BBOX";
        }
        if (exists $params->{source}->{area}->{geometry}) {
            $this->{extent} = $params->{source}->{area}->{geometry};
            $this->{area} = "EXTENT";
        }
        if (exists $params->{source}->{area}->{list}) {
            $this->{list} = $params->{source}->{area}->{list};
            $this->{area} = "LIST";
        }
    }
    elsif ($this->{type} eq "POSTGRESQL") {
        $this->{database} = ROK4::PREGENERATION::SourceDatabase->new($params->{source});
        if (! defined $this->{database}) {
            ERROR("Cannot load a POSTGRESQL source");
            return FALSE;
        }
        $this->{srs} = $params->{source}->{srs};

        my @data_bbox = $this->{database}->computeBBox();
        INFO(join(",",@data_bbox));
            
        if (exists $params->{source}->{area}->{bbox}) {
            $this->{bbox} = $params->{source}->{area}->{bbox};
            $this->{area} = "BBOX";

            # On va restreindre la bbox fournie à l'étendue réelle des données en base
            $this->{bbox}->[0] = max($data_bbox[0], $this->{bbox}->[0]); # xmin
            $this->{bbox}->[1] = max($data_bbox[1], $this->{bbox}->[1]); # ymin
            $this->{bbox}->[2] = min($data_bbox[2], $this->{bbox}->[2]); # xmax
            $this->{bbox}->[3] = min($data_bbox[3], $this->{bbox}->[3]); # ymax

            if ($this->{bbox}->[2] <= $this->{bbox}->[0] || $this->{bbox}->[3] <= $this->{bbox}->[1]) {
                ERROR("Data extent in PostgreSQL and provided bbox are not intersected");
                return FALSE;
            }
        }
        elsif (exists $params->{source}->{area}->{geometry}) {
            $this->{extent} = $params->{source}->{area}->{geometry};
            $this->{area} = "EXTENT";
        }
        elsif (exists $params->{source}->{area}->{list}) {
            $this->{list} = $params->{source}->{area}->{list};
            $this->{area} = "LIST";
        }
        else {
            # On va faire le calcul sur l'ensemble des données en base
            $this->{bbox} = \@data_bbox;
            $this->{area} = "BBOX";
        }


        $this->{generator_name} = $params->{generator}->{name};
        if (exists($params->{generator}->{options}) && defined $params->{generator}->{options}) {
            $this->{generator_options} = $params->{generator}->{options};
        }
    }
    elsif ($this->{type} eq "PYRAMIDS") {
        $this->{pyramids} = ROK4::PREGENERATION::SourcePyramid->new($this->{bottomID}, $this->{topID}, $params->{source}->{descriptors});
        if (! defined $this->{pyramids}) {
            ERROR("Cannot load a PYRAMIDS source");
            return FALSE;
        }
        $this->{srs} = $this->{pyramids}->getSRS();

        if (exists $params->{source}->{area}->{bbox}) {
            $this->{bbox} = $params->{source}->{area}->{bbox};
            $this->{area} = "BBOX";
        }
        if (exists $params->{source}->{area}->{geometry}) {
            $this->{extent} = $params->{source}->{area}->{geometry};
            $this->{area} = "EXTENT";
        }
    }

    if ($this->{bottomID} eq "<AUTO>" && $this->{type} ne "IMAGES") {
        ERROR("Auto detect the bottom level is only possible with image source");
        return FALSE;
    }

    if ($this->{area} eq "LIST") {
        # On a fourni un fichier contenant la liste des images (I et J) à générer
        my $file = $this->{list};
        if (! -e $file) {
            ERROR("Parameter 'list' value have to be an existing file ($file)");
            return FALSE ;
        }
    }
    elsif ($this->{area} eq "BBOX") {
        INFO("là");
        $this->{extent} = ROK4::Core::ProxyGDAL::geometryFromBbox(@{$this->{bbox}});
    }
    elsif ($this->{area} eq "EXTENT") {
        my $file = $this->{extent};
        $this->{extent} = ROK4::Core::ProxyGDAL::geometryFromFile($file);
        if (! defined $this->{extent}) {
            ERROR("Cannot create a OGR geometry from the file $file");
            return FALSE ;
        }

        my ($xmin,$ymin,$xmax,$ymax) = ROK4::Core::ProxyGDAL::getBbox($this->{extent});
        if (! defined $xmin) {
            ERROR("Cannot calculate bbox from the OGR Geometry");
            return FALSE;
        }
        $this->{bbox} = [$xmin,$ymin,$xmax,$ymax];
    }

    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getSRS
sub getSRS {
    my $this = shift;
    return $this->{srs};
}

# Function: getArea
sub getArea {
    my $this = shift;
    return $this->{area};
}

# Function: getExtent
sub getExtent {
    my $this = shift;
    return $this->{extent};
}

# Function: getBbox
sub getBbox {
    my $this = shift;
    return $this->{bbox};
}

# Function: getList
sub getList {
    my $this = shift;
    return $this->{list};
}


# Function: getSource
sub getSource {
    my $this = shift;
    if ($this->{type} eq "WMS") {
        return $this->{wms};
    }
    elsif ($this->{type} eq "POSTGRESQL") {
        return $this->{database};
    }
    elsif ($this->{type} eq "IMAGES") {
        return $this->{images};
    }
    elsif ($this->{type} eq "VECTORS") {
        return $this->{vectors};
    }
    elsif ($this->{type} eq "PYRAMIDS") {
        return $this->{pyramids};
    }
    return undef;
}

# Function: getType
sub getType {
    my $this = shift;
    return $this->{type};
}

# Function: getGenerator
sub getGenerator {
    my $this = shift;
    return $this->{generator_name};
}

# Function: getGeneratorOptions
sub getGeneratorOptions {
    my $this = shift;
    return $this->{generator_options};
}

# Function: getBottomID
sub getBottomID {
    my $this = shift;
    return $this->{bottomID};
}

# Function: getTopID
sub getTopID {
    my $this = shift;
    return $this->{topID};
}

# Function: getBottomOrder
sub getBottomOrder {
    my $this = shift;
    return $this->{bottomOrder};
}

# Function: getTopOrder
sub getTopOrder {
    my $this = shift;
    return $this->{topOrder};
}

# Function: getPixel
sub getPixel {
    my $this = shift;
    if (defined $this->{images}) {
        return $this->{images}->getPixel();
    }
    if (defined $this->{pyramids}) {
        return $this->{pyramids}->getPixel();
    }
    return undef;
}

=begin nd
Function: setBottomOrder

Parameters (list):
    bottomOrder - integer - Bottom level order to set
=cut
sub setBottomOrder {
    my $this = shift;
    my $bottomOrder = shift;
    $this->{bottomOrder} = $bottomOrder;
}
=begin nd
Function: setBottomID

Parameters (list):
    bottomID - string - Bottom level identifiant to set
=cut
sub setBottomID {
    my $this = shift;
    my $bottomID = shift;
    $this->{bottomID} = $bottomID;
}

=begin nd
Function: setTopOrder

Parameters (list):
    topOrder - integer - Top level order to set
=cut
sub setTopOrder {
    my $this = shift;
    my $topOrder = shift;
    $this->{topOrder} = $topOrder;
}

=begin nd
Function: setTopID

Parameters (list):
    topID - string - Top level identifiant to set
=cut
sub setTopID {
    my $this = shift;
    my $topID = shift;
    $this->{topID} = $topID;
}

1;
__END__
