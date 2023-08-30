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
File: SourceVector.pm

Class: ROK4::PREGENERATION::SourceVector

(see libperlauto/ROK4_Core_SourceVector.png)

Define a data source, with georeferenced image directory.

Using:
    (start code)
    use ROK4::PREGENERATION::SourceVector;

    # SourceVector object creation
    my $objSourceVector = ROK4::PREGENERATION::SourceVector->new({
        directory => "/home/ign/DATA",
        srs => "EPSG:4326"
    });
    (end code)

Attributes:
    PATHIMG - string - Path to images directory.
    vectors - <ROK4::Core::GeoVector> array - Vector files, found in PATHIMG and subdirectories
    srs - string - SRS of the georeferenced images
    tables - hash - all informations about wanted tables
|        {
|            'public.departement' => {
|                'filter' => '',
|                'final_name' => 'departement',
|                'attributes' => {
|                    'ogc_fid' => {
|                        'count' => 101,
|                        'type' => 'integer'
|                    },
|                    'nom_dep' => {
|                        'type' => 'character varying(30)',
|                        'count' => 101
|                    },
|                    'insee_reg' => {
|                        'type' => 'character varying(2)',
|                        'count' => 18
|                    },
|                    'chf_dep' => {
|                        'count' => 101,
|                        'type' => 'character varying(5)'
|                    },
|                    'id' => {
|                        'count' => 101,
|                        'type' => 'character varying(24)'
|                    },
|                    'insee_dep' => {
|                        'type' => 'character varying(3)',
|                        'count' => 101
|                    },
|                    'nom_dep_m' => {
|                        'count' => 101,
|                        'type' => 'character varying(30)'
|                    }
|                },
|                'schema' => 'public',
|                'geometry' => {
|                                'name' => 'wkb_geometry',
|                                'type' => 'MULTIPOLYGON'
|                                },
|                'native_name' => 'departement'
|            }
|        }
    
=cut

################################################################################

package ROK4::PREGENERATION::SourceVector;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use List::Util qw(min max);

use File::Path qw(make_path);

use ROK4::Core::GeoVector;

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

SourceVector constructor. Bless an instance.

Parameters (hash):
    directory - string - Path to files' directory, to analyze.
    srs - string - SRS of the vector files
    
See also:
    <_init>, <computeSourceVector>
=cut
sub new {
    my $class = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        PATHIMG => undef,
        #
        images  => [],
        srs => undef
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($params));

    return undef if (! $this->computeSourceVector());

    return $this;
}

=begin nd
Function: _init

Checks and stores informations.

Parameters (hash):
    directory - string - Path to files' directory, to analyze.
    srs - string - SRS of the vector files
    
=cut
sub _init {
    my $this   = shift;
    my $params = shift;
        
    # init. params    
    $this->{PATHIMG} = $params->{directory};
    $this->{srs} = $params->{srs};
    
    if (! -d $this->{PATHIMG}) {
        ERROR (sprintf "Directory image ('%s') doesn't exist !",$this->{PATHIMG});
        return FALSE;
    }

    return TRUE;

}

####################################################################################################
#                                 Group: Images treatments                                         #
####################################################################################################

=begin nd
Function: computeSourceVector

Detects all handled files in *PATHIMG* and subdirectories and creates a corresponding <GeoVector> object. Determines data's components and check them.

See also:
    <getListVectors>
=cut
sub computeSourceVector {
    my $this = shift;

    my $search = {
        vectors => [],
    };

    if (! $this->getListVectors($this->{PATHIMG}, $search)) {
        ERROR ("Cannot browse vector directory !");
        return FALSE;
    }

    my @paths = @{$search->{vectors}};
    if (scalar @paths == 0) {
        ERROR ("No handled files found in ".$this->{PATHIMG});
        return FALSE;
    }
    
    foreach my $filepath (@paths) {

        my $objGeoVector = ROK4::Core::GeoVector->new($filepath, $this->{srs});

        if (! defined $objGeoVector) {
            ERROR ("Can not load vector file ('$filepath') !");
            return FALSE;
        }

        my $table = $objGeoVector->getTable();

        if (exists $this->{$table->{final_name}}) {
            ERROR (sprintf "Several vector files in the VECTORS source own the same table name '%s'", $table->{final_name});
            return FALSE;
        }
        
        $this->{$table->{final_name}} = $table;

        push(@{$this->{vectors}}, $objGeoVector);
    }

    if (scalar(@{$this->{vectors}}) == 0) {
        ERROR (sprintf "Can not found vector source in '%s' !",$this->{PATHIMG});
        return FALSE;
    }

    return TRUE;
}

=begin nd
Function: getListVectors

Recursive method to browse a directory and list all handled file. Returns an hash containing the vector file path's array.
| {
|     vectors => [...],
| };

Parameters (list):
    directory - string - Path to directory, to browse.
    search - hash - Hash reference, to store vector' paths.
=cut  
sub getListVectors {
    my $this = shift;
    my $directory = shift;
    my $search = shift;

    if (! opendir (DIR, $directory)) {
        ERROR("Can not open directory cache (%s) ?",$directory);
        return FALSE;
    }

    foreach my $entry (readdir DIR) {
        next if ($entry =~ m/^\.{1,2}$/);

        $entry = File::Spec->catdir($directory, $entry);

        # Si on a à faire à un dossier, on appelle récursivement la méthode pourle parcourir
        if ( -d $entry) {
            if (! $this->getListVectors($entry, $search)) {
                return FALSE;
            }
        }

        # Si le fichier n'a pas l'extension GEOBUF, JSON ou GEOJSON, on ne le traite pas
        next if ( $entry !~ /.*\.(geojson)$/i && $entry !~ /.*\.(json)$/i && $entry !~ /.*\.(geobuf)$/i);

        push @{$search->{vectors}}, $entry;
    }

    return TRUE;
}

=begin nd
Function: computeBBox

Calculate extrem limits of vectors, in the source SRS.

Returns a double list : (xMin,yMin,xMax,yMax).
=cut
sub computeBBox {
    my $this = shift;

    my ($xmin,$ymin,$xmax,$ymax) = $this->{vectors}->[0]->getBBox();

    foreach my $objVector (@{$this->{vectors}}) {
        $xmin = min($xmin, $objVector->getXmin());
        $xmax = max($xmax, $objVector->getXmax());
        $ymin = min($ymin, $objVector->getYmin());
        $ymax = max($ymax, $objVector->getYmax());
    }

    return ($xmin,$ymin,$xmax,$ymax);
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getSRS
sub getSRS {
    my $this = shift;
    return $this->{srs};
}

# Function: getPathsList
sub getPathsList {
    my $this = shift;
    # copy !
    my @vectors;
    foreach my $v (@{$this->{vectors}}) {
        push(@vectors, $v->getCompletePath());
    }
    return join(" ", @vectors);
}

# Function: getTables
sub getTables {
    my $this = shift;
    return $this->{tables};
}

1;
__END__
