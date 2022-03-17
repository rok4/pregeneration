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
File: Forest.pm

Class: ROK4::PREGENERATION::Forest

(see libperlauto/Core_Forest.png)

Creates and manages all graphs, <NNGraph> and <QTree>.

(see ROK4GENERATION/forest.png)

We have several kinds of graphs and their using have to be transparent for the forest. That's why we must define functions for all graph's types (as an interface) :
    - computeYourself() : <NNGraph::computeYourself>, <QTree::computeYourself>
    - containsNode(level, i, j) : <NNGraph::containsNode>, <QTree::containsNode>

Using:
    (start code)
    use ROK4::PREGENERATION::Forest

    my $Forest = ROK4::PREGENERATION::Forest->new(
        $objPyramid, # a ROK4::Core::PyramidRaster or ROK4::Core::PyramidVector object
        $objDSL, # a ROK4::PREGENERATION::SourceLoader object
        $param_process, # a hash with following keys : job_number, path_temp, path_temp_common and path_shell
    );
    (end code)

Attributes:
    pyramid - <ROK4::Core::PyramidRaster> or <ROK4::Core::PyramidVector> - Images' pyramid to generate, thanks to one or several graphs.
    graphs - <ROK4::PREGENERATION::QTree> or <ROK4::PREGENERATION::NNGraph> array - Graphs composing the forest, one per data source.
    scripts - <ROK4::PREGENERATION::Script> array - Scripts, whose execution generate the images' pyramid.
    splitNumber - integer - Number of script used for work parallelization.

=cut

################################################################################

package ROK4::PREGENERATION::Forest;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;
use List::Util qw(min max);
use Cwd;
use File::Spec;

# My module
use ROK4::PREGENERATION::QTree;
use ROK4::PREGENERATION::NNGraph;
use ROK4::Core::Array;

use ROK4::BE4::Shell;
use ROK4::FOURALAMO::Shell;

use ROK4::Core::PyramidRaster;
use ROK4::Core::PyramidVector;
use ROK4::PREGENERATION::Script;
use ROK4::PREGENERATION::Source;


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

Forest constructor. Bless an instance.

Parameters (list):
    pyramid - <ROK4::Core::PyramidRaster> or <ROK4::Core::PyramidVector> - Output pyramid, generated by this forest.
    sources - <ROK4::PREGENERATION::Source> array reference - List of data sources
    params - hash reference - All configuration

See also:
    <_load>
=cut
sub new {
    my $class = shift;
    my $pyramid = shift;
    my $sources = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        pyramid     => undef,
        graphs      => [],
        scripts     => {},
        splitNumber => undef
    };

    bless($this, $class);

    # it's an object and it's mandatory !
    if (! defined $pyramid || (ref ($pyramid) ne "ROK4::Core::PyramidRaster" && ref ($pyramid) ne "ROK4::Core::PyramidVector")) {
        ERROR("We need a ROK4::Core::PyramidRaster or ROK4::Core::PyramidVector to create a Forest");
        return undef;
    }
    $this->{pyramid} = $pyramid;
    
    # load. class
    return undef if (! $this->_load($sources, $params) );
    
    INFO (sprintf "Graphs' number : %s",scalar @{$this->{graphs}});

    return $this;
}

=begin nd
Function: _load

Creates a <ROK4::PREGENERATION::NNGraph> or a <ROK4::PREGENERATION::QTree> object per data source. Using a QTree is faster but it does'nt match all cases.

All differences between different kinds of graphs are handled in respective classes, in order to be imperceptible for users.

Only scripts creation and initial organization are managed by the forest.

Parameters (list):
    sources - <ROK4::PREGENERATION::Source> array reference - List of data sources
    params - hash reference - All configuration

=cut
sub _load {
    my $this = shift;
    my $sources = shift;
    my $params = shift;

    my $TMS = $this->{pyramid}->getTileMatrixSet();
    my $isQTree = $TMS->isQTree();
    
    ######### PARAM PROCESS ###########
    
    $this->{splitNumber} = $params->{process}->{parallelization};
    my $tempDir = File::Spec->rel2abs($params->{process}->{directories}->{local_tmp});
    my $commonTempDir = File::Spec->rel2abs($params->{process}->{directories}->{shared_tmp});
    my $scriptDir = File::Spec->rel2abs($params->{process}->{directories}->{scripts});

    ############# SHELL #############

    my $scriptInit = undef;
    my $is_update = ($params->{pyramid}->{type} ne "GENERATION");
    if (ref ($this->{pyramid}) eq "ROK4::Core::PyramidRaster") {
        # Si on génère une pyramide raster, c'est que nous utilisons l'outil BE4, et des variables sont à initialiser dans la librairie des commandes Shell pour BE4

        if ($this->{pyramid}->ownMasks()) {
            # Si on souhaite avoir des masques dans la pyramide de sortie, il faut les utiliser tout du long des calculs
            $params->{pyramid}->{mask}->{use} = "TRUE";
        }

        if (! ROK4::BE4::Shell::setGlobals($this->{splitNumber}, $tempDir, $commonTempDir, $scriptDir, $params->{pyramid}->{mask}->{use}, $is_update)) {
            ERROR ("Impossible d'initialiser la librairie des commandes Shell pour BE4");
            return FALSE;
        }
        $scriptInit = ROK4::BE4::Shell::getScriptInitialization(
            $this->{pyramid},
            $params->{process}->{style},
            $params->{process}->{nodata}
        );
    } else {
        if (! ROK4::FOURALAMO::Shell::setGlobals($this->{splitNumber}, $tempDir, $commonTempDir, $scriptDir, $is_update)) {
            ERROR ("Impossible d'initialiser la librairie des commandes Shell pour 4ALAMO");
            return FALSE;
        }
        $scriptInit = ROK4::FOURALAMO::Shell::getScriptInitialization(
            $this->{pyramid}
        );
    }
    
    ############# SCRIPTS #############
    # We create ROK4::PREGENERATION::Script objects and initialize them (header)

    if ($isQTree) {
        #### QTREE CASE
        $this->{scripts} = ROK4::PREGENERATION::QTree::defineScripts($scriptInit, $this->{pyramid});
    } else {
        #### NN GRAPH CASE
        $this->{scripts} = ROK4::PREGENERATION::NNGraph::defineScripts($scriptInit, $this->{pyramid});
    }
    
    ############# GRAPHS #############

    foreach my $s (@{$sources}) {
        
        # Creation of QTree or NNGraph object
        my $graph = undef;
        if ($isQTree) {
            $graph = ROK4::PREGENERATION::QTree->new($this, $s);
        } else {
            $graph = ROK4::PREGENERATION::NNGraph->new($this, $s);
        };
                
        if (! defined $graph) {
            ERROR(sprintf "Can not create a graph for datasource with bottom level %s !", $s->getBottomID());
            return FALSE;
        }
        
        push @{$this->{graphs}},$graph;
    }

    return TRUE;
}


####################################################################################################
#                                  Group: Graphs tools                                             #
####################################################################################################

=begin nd
Function: containsNode

Returns a boolean : TRUE if the node belong to this forest, FALSE otherwise (if a parameter is not defined too).

Parameters (list):
    level - string - Level ID of the node we want to know if it is in the forest.
    col - integer - Column of the node we want to know if it is in the forest.
    row - integer - Row of the node we want to know if it is in the forest.
=cut
sub containsNode {
    my $this = shift;
    my $level = shift;
    my $col = shift;
    my $row = shift;

    return FALSE if (! defined $level || ! defined $col || ! defined $row);
    
    foreach my $graph (@{$this->{graphs}}) {
        return TRUE if ($graph->containsNode($level,$col,$row));
    }
    
    return FALSE;
}

=begin nd
Function: computeGraphs

Computes each <ROK4::PREGENERATION::NNGraph> or <ROK4::PREGENERATION::QTree> one after the other and closes scripts to finish.

See Also:
    <ROK4::PREGENERATION::NNGraph::computeYourself>, <ROK4::PREGENERATION::QTree::computeYourself>
=cut
sub computeGraphs {
    my $this = shift;
    
    my $graphInd = 1;
    my $graphNumber = scalar @{$this->{graphs}};
    
    foreach my $graph (@{$this->{graphs}}) {
        if (! $graph->computeYourself()) {
            ERROR(sprintf "Cannot compute graph $graphInd/$graphNumber");
            return FALSE;
        }
        INFO("Graph $graphInd/$graphNumber computed");
        $graphInd++;
    }
    
    if ($this->{pyramid}->getTileMatrixSet()->isQTree()) {
        ROK4::PREGENERATION::QTree::closeScripts($this->{scripts});
    } else {
        ROK4::PREGENERATION::NNGraph::closeScripts($this->{scripts});
    }
    
    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getGraphs
sub getGraphs {
    my $this = shift;
    return $this->{graphs}; 
}

# Function: getPyramid
sub getPyramid {
    my $this = shift;
    return $this->{pyramid}; 
}

# Function: getScripts
sub getScripts {
    my $this = shift;
    return $this->{scripts};
}

####################################################################################################
#                                Group: Export methods                                             #
####################################################################################################

=begin nd
Function: exportForDebug

Returns all informations about the forest. Useful for debug.

Example:
    (start code)
    (end code)
=cut
sub exportForDebug {
    my $this = shift ;
    
    my $export = "";
    
    $export .= sprintf "\n Object ROK4::PREGENERATION::Forest :\n";

    $export .= "\t Graph :\n";
    $export .= sprintf "\t Number of graphs in the forest : %s\n", scalar @{$this->{graphs}};
    
    $export .= "\t Scripts :\n";
    $export .= sprintf "\t Parallelization level : %s\n", $this->{splitNumber};
    
    return $export;
}

1;
__END__
