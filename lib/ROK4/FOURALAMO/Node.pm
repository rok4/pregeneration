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
File: Node.pm

Class: ROK4::FOURALAMO::Node

(see libperlauto/ROK4_Core_Node.png)

Describe a node of a <ROK4::PREGENERATION::QTree> or a <ROK4::PREGENERATION::NNGraph>. Allow different storage (FileSystem, Ceph, Swift).

Using:
    (start code)
    use ROK4::FOURALAMO::Node

    my $tm = ROK4::Core::TileMatrix->new(...)
    
    my $graph = ROK4::Core::Qtree->new(...)
    #or
    my $graph = ROK4::PREGENERATION::NNGraph->new(...)
    
    my $node = ROK4::FOURALAMO::Node->new({
        col => 51,
        row => 756,
        tm => $tm,
        graph => $graph
    });
    (end code)

Attributes:
    col - integer - Column, according to the TMS grid.
    row - integer - Row, according to the TMS grid.

    storageType - string - Final storage type for the node : "FILE", "CEPH" or "S3"

    weight - integer - Node's weight : 1 + children's weights

    workImageBasename - string - <LEVEL>_<COL>_<ROW>_I

    tm - <ROK4::Core::TileMatrix> - Tile matrix associated to the level which the node belong to.
    graph - <ROK4::PREGENERATION::NNGraph> or <ROK4::PREGENERATION::QTree> - Graph which contains the node.

    script - <ROK4::PREGENERATION::Script> - Script in which the node will be generated
=cut

################################################################################

package ROK4::FOURALAMO::Node;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use List::Util qw(min max);

use File::Spec ;
use Data::Dumper ;
use ROK4::Core::Base36 ;


################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

Node constructor. Bless an instance.

Parameters (hash):
    type - string - Final storage type : 'FILE', 'CEPH', 'S3', 'SWIFT'
    col - integer - Node's column
    row - integer - Node's row
    tm - <ROK4::Core::TileMatrix> - Tile matrix of the level which node belong to
    graph - <ROK4::PREGENERATION::NNGraph> or <ROK4::PREGENERATION::QTree> - Graph containing the node.

See also:
    <_init>
=cut
sub new {
    my $class = shift;
    my $params = shift;
    
    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        col => undef,
        row => undef,
        tm => undef,
        graph => undef,

        weight => 1,

        script => undef,

        workImageBasename => undef,
        
        # Stockage final de la dalle dans la pyramide pour ce noeud
        storageType => undef
    };
    
    bless($this, $class);
    
    # mandatory parameters !
    if (! defined $params->{col}) {
        ERROR("Node's column is undef !");
        return undef;
    }
    if (! defined $params->{row}) {
        ERROR("Node's row is undef !");
        return undef;
    }
    if (! defined $params->{tm}) {
        ERROR("Node's tile matrix is undef !");
        return undef;
    }
    if (! defined $params->{graph}) {
        ERROR("Node's graph is undef !");
        return undef;
    }

    # init. params    
    $this->{col} = $params->{col};
    $this->{row} = $params->{row};
    $this->{tm} = $params->{tm};
    $this->{graph} = $params->{graph};
    $this->{storageType} = $this->{graph}->getPyramid()->getStorageType();
    $this->{workImageBasename} = sprintf "%s_%s_%s_I", $this->getLevel(), $this->{col}, $this->{row};
        
    return $this;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getLevel
sub getLevel {
    my $this = shift;
    return $this->{tm}->getID;
}

# Function: getTM
sub getTM {
    my $this = shift;
    return $this->{tm};
}

# Function: getGraph
sub getGraph {
    my $this = shift;
    return $this->{graph};
}

# Function: getSlabPath
sub getSlabPath {
    my $this = shift;
    my $type = shift;
    my $full = shift;

    return $this->{graph}->getPyramid()->getSlabPath($type, $this->getLevel(), $this->getCol(), $this->getRow(), $full);
}


# Function: getSlabSize
sub getSlabSize {
    my $this = shift;

    return $this->{graph}->getPyramid()->getSlabSize($this->getLevel());
}

# Function: getCol
sub getCol {
    my $this = shift;
    return $this->{col};
}

# Function: getRow
sub getRow {
    my $this = shift;
    return $this->{row};
}

# Function: getStorageType
sub getStorageType {
    my $this = shift;
    return $this->{storageType};
}

########## weight 

# Function: getWeight
sub getWeight {
    my $this = shift;
    return $this->{weight};
}

=begin nd
Function: incrementWeight

Add one
=cut
sub incrementWeight {
    my $this = shift;
    $this->{weight}++;
}

########## scripts 

# Function: getScript
sub getScript {
    my $this = shift;
    return $this->{script};
}

=begin nd
Function: setScript

Parameters (list):
    script - <ROK4::PREGENERATION::Script> - Script to set.
=cut
sub setScript {
    my $this = shift;
    my $script = shift;
    
    if (! defined $script || ref ($script) ne "ROK4::PREGENERATION::Script") {
        ERROR("We expect to a ROK4::PREGENERATION::Script object.");
    }
    
    $this->{script} = $script; 
}

########## work

=begin nd
Function: getWorkBaseName

Returns the work image base name (no extension) : "level_col_row"
=cut
sub getWorkBaseName {
    my $this = shift;
    return (sprintf "%s_%s_%s", $this->getLevel, $this->{col}, $this->{row});
}

# Function: getUpperLeftTile
sub getUpperLeftTile {
    my $this = shift;

    return (
        $this->{col} * $this->{graph}->getPyramid()->getTilesPerWidth(),
        $this->{row} * $this->{graph}->getPyramid()->getTilesPerHeight()
    );
}

# Function: getBBox
sub getBBox {
    my $this = shift;
    my $crop = shift;
    
    my @Bbox = $this->{tm}->indicesToBbox(
        $this->{col},
        $this->{row},
        $this->{graph}->getPyramid()->getTilesPerWidth(),
        $this->{graph}->getPyramid()->getTilesPerHeight(),
        $crop
    );
    
    return @Bbox;
}

=begin nd
Function: getChildren

Returns a <ROK4::FOURALAMO::Node> array, containing real children (max length = 4), an empty array if the node is a leaf.
=cut
sub getChildren {
    my $this = shift;
    return $this->{graph}->getChildren($this);
}

####################################################################################################
#                              Group: Processing functions                                         #
####################################################################################################

=begin nd
Function: makeJsons

Parameters (list):
    datasource - <ROK4::PREGENERATION::Source> - To use to extract vector data.

Code example:
    (start code)
    MakeJson "273950.309374068154368 6203017.719398627074048 293518.188615073275904 6222585.598639632195584" "host=postgis.ign.fr dbname=bdtopo user=ign password=PWD port=5432" "SELECT geometry FROM bdtopo_2018.roads WHERE type='highway'" roads
    (end code)

Returns:
    TRUE if success, FALSE if failure
=cut
sub makeJsons {
    my $this = shift;
    my $datasource = shift;

    my $dburl = $datasource->getSource()->getInfos();
    my $srcSrs = $datasource->getSRS();

    my @tables = $datasource->getSource()->getSqlExports();

    my @tmp = $this->getBBox(TRUE);

    my @datasource_bbox = @{$datasource->getBbox()};

    my @slab_src_bbox = ROK4::Core::ProxyGDAL::convertBBox( $this->getGraph()->getCoordTransPyramidDatasource(), $this->getBBox(TRUE));
    # On va agrandir la bbox de 5% pour être sur de tout avoir
    my @slab_src_bbox_extended = @slab_src_bbox;
    my $w = ($slab_src_bbox[2] - $slab_src_bbox[0])*0.05;
    my $h = ($slab_src_bbox[3] - $slab_src_bbox[1])*0.05;
    $slab_src_bbox_extended[0] -= $w;
    $slab_src_bbox_extended[2] += $w;
    $slab_src_bbox_extended[1] -= $h;
    $slab_src_bbox_extended[3] += $h;

    my @spat_bbox = (
        max($slab_src_bbox_extended[0], $datasource_bbox[0]),
        max($slab_src_bbox_extended[1], $datasource_bbox[1]),
        min($slab_src_bbox_extended[2], $datasource_bbox[2]),
        min($slab_src_bbox_extended[3], $datasource_bbox[3])
    );

    my $spat_bbox_string = join(" ", @spat_bbox);

    for (my $i = 0; $i < scalar @tables; $i += 2) {
        my $sql = $tables[$i];
        my $dstTableName = $tables[$i+1];
        $this->{script}->write(sprintf "MakeJson \"$srcSrs\" \"$spat_bbox_string\" \"$spat_bbox_string\" \"$dburl\" '$sql' $dstTableName\n");
    }

    return TRUE;
}

=begin nd
Function: pbf2cache

Example:
|    PushSlab 10 6534 9086 DATA/10/AB/CD.tif

Returns:
    TRUE if success, FALSE if failure
=cut
sub pbf2cache {
    my $this = shift;

    my $pyrName = $this->getSlabPath("DATA", FALSE);
    $this->{script}->write(sprintf "PushSlab %s %s %s %s\n", $this->getLevel(), $this->getUpperLeftTile(), $pyrName);
    
    return TRUE;
}

=begin nd
Function: makeTiles

Parameters (list):
    datasource - <ROK4::PREGENERATION::Source> - To use to tile vector data.

Returns:
    TRUE if success, FALSE if failure
=cut
sub makeTiles {
    my $this = shift;
    my $datasource = shift;

    # ${TMP_DIR}/jsons/*.json
    my $sources = '${TMP_DIR}/jsons/*.json';
    if ($datasource->getType() eq "VECTORS") {
        $sources = $datasource->getSource()->getPathsList();
    }

    $this->{script}->write(sprintf "MakeTiles \"$sources\" %s %s \"%s\"\n", $this->getGraph()->getTopID(), $this->getGraph()->getBottomID(), $datasource->getTippecanoeOptions());

    return TRUE;
}

1;
__END__