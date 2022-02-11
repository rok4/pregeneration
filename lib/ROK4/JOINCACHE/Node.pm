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

Class: ROK4::JOINCACHE::Node

(see libperlauto/JOINCACHE_Node.png)

Descibe a node

Using:
    (start code)
    use ROK4::JOINCACHE::Node

    my $node = ROK4::JOINCACHE::Node->new(51, 756, "12", 2);
    (end code)

Attributes:
    col - integer - Column
    row - integer - Row
    level - string - Level's identifiant
    pyramid - <ROK4::Core::PyramidRaster> - Pyramid which node belong to
    script - <ROK4::Core::Script> - Script in which the node will be generated
    sources - hash array - Source images from which this node is generated. One image source :
|               img - string - Absolute path to the image
|               msk - string - Absolute path to the associated mask (optionnal)
|               sourcePyramid - <ROK4::Core::PyramidRaster> - Pyramid which image belong to
=cut

################################################################################

package ROK4::JOINCACHE::Node;

use strict;
use warnings;

use Log::Log4perl qw(:easy);

use File::Spec;
use Data::Dumper;

use ROK4::Core::Base36;
use ROK4::Core::ProxyGDAL;
use ROK4::Core::PyramidRaster;

use ROK4::JOINCACHE::Shell;



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

Node constructor. Bless an instance.

Parameters (list):
    level - string - Node's level ID
    col - integer - Node's column
    row - integer - Node's row
    pyramid - <ROK4::Core::PyramidRaster> - Pyramid which node belong to
    sourcePyramids - array - Pyramids and limits to use as sources

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
        level => undef,
        pyramid => undef,
        script => undef,
        sources => []
    };
    
    bless($this, $class);
    
    # init. class
    if (! $this->_init($params)) {
        ERROR("Node initialization failed.");
        return undef;
    }
    
    return $this;
}

=begin nd
Function: _init

Check and store node's attributes values.

Parameters (list):
    level - string - Node's level ID
    col - integer - Node's column
    row - integer - Node's row
=cut
sub _init {
    my $this = shift;
    my $params = shift;
    
    # mandatory parameters !
    if (! exists $params->{level} || ! defined $params->{level}) {
        ERROR("Node's level is undefined !");
        return FALSE;
    }
    if (! exists $params->{col} || ! defined $params->{col}) {
        ERROR("Node's column is undefined !");
        return FALSE;
    }
    if (! exists $params->{row} || ! defined $params->{row}) {
        ERROR("Node's row is undefined !");
        return FALSE;
    }
    if (! exists $params->{pyramid} || ! defined $params->{pyramid}) {
        ERROR("Node's pyramid is undefined !");
        return FALSE;
    }
    if (! exists $params->{sources} || ! defined $params->{sources}) {
        ERROR("Node's pyramid is undefined !");
        return FALSE;
    }
    
    # init. params
    $this->{col} = $params->{col};
    $this->{row} = $params->{row};
    $this->{level} = $params->{level};
    $this->{pyramid} = $params->{pyramid};
    $this->{sources} = $params->{sources};
    
    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getPyramid
sub getPyramid {
    my $this = shift;
    return $this->{pyramid};
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

# Function: getLevel
sub getLevel {
    my $this = shift;
    return $this->{level};
}

=begin nd
Function: setScript

Parameters (list):
    script - <Script> - Script to set.
=cut
sub setScript {
    my $this = shift;
    my $script = shift;

    if (! defined $script || ref ($script) ne "ROK4::Core::Script") {
        ERROR("We expect to have a ROK4::Core::Script object.");
    }

    $this->{script} = $script;
}

=begin nd
Function: getWorkBaseName

Returns the work image base name (no extension) : "level_col_row", or "level_col_row_suffix" if suffix is defined.

Parameters (list):
    suffix - string - Optionnal, suffix to add to the work name
=cut
sub getWorkBaseName {
    my $this = shift;
    my $suffix = shift;
    
    # si un suffix est précisé
    return (sprintf "%s_%s_%s_%s", $this->{level}, $this->{col}, $this->{row}, $suffix) if (defined $suffix);
    # si pas de suffix
    return (sprintf "%s_%s_%s", $this->{level}, $this->{col}, $this->{row});
}

=begin nd
Function: getWorkName

Returns the work image name : "level_col_row.tif", or "level_col_row_suffix.tif" if suffix is defined.

Parameters (list):
    prefix - string - Optionnal, suffix to add to the work name
=cut
sub getWorkName {
    my $this = shift;
    my $suffix = shift;
    
    return $this->getWorkBaseName($suffix).".tif";
}

# Function: getSources
sub getSources {
    my $this = shift;
    return $this->{sources};
}

=begin nd
Function: getSource

Parameters (list):
    ind - integer - Index of the wanted source image

Returns
    A source image, as an hash :
|               img - string - Path to the image (object or file)
|               msk - string - Path to the associated mask (optionnal, object or file)
|               sourcePyramid - <ROK4::Core::PyramidRaster> - Pyramid which image belong to
=cut
sub getSource {
    my $this = shift;
    my $ind = shift;
    return $this->{sources}->[$ind];
}

# Function: getSourcesNumber
sub getSourcesNumber {
    my $this = shift;
    return scalar @{$this->{sources}};
}

# Function: getScript
sub getScript {
    my $this = shift;
    return $this->{script};
}

####################################################################################################
#                              Group: Processing functions                                         #
####################################################################################################


=begin nd
Function: linkSlab

Parameters (list):
    targetRoot - string - Root of target slab
    slabName - string - Slab name, common to target and link
=cut
sub linkSlab {
    my $this = shift;
    my $targetRoot = shift;
    my $slabName = shift;

    $this->{script}->write(sprintf "LinkSlab $targetRoot/$slabName $slabName\n");
}


=begin nd
Function: convert

Called when only one source but not compatible
=cut
sub convert {
    my $this = shift;

    my $nodeName = $this->getWorkBaseName();

    my $sourceImage = $this->getSource(0);

    $this->{script}->write(sprintf "PullSlab %s/%s ${nodeName}_I.tif\n", $sourceImage->{img}->[0], $sourceImage->{img}->[1]);
    $this->{script}->write(sprintf "PushSlab ${nodeName}_I.tif %s\n\n", $sourceImage->{img}->[1]);
    
    return TRUE;
}

=begin nd
Function: overlayNtiff

Write commands in the current script to merge N (N could be 1) images according to the merge method. We use *tiff2rgba* to convert into work format and *overlayNtiff* to merge. Masks are treated if needed. Code is store into the node.

If just one input image, overlayNtiff is used to change the image's properties (samples per pixel for example). Mask is not treated (masks have always the same properties and a symbolic link have been created).

Returns:
    A boolean, TRUE if success, FALSE otherwise.
=cut
sub overlayNtiff {
    my $this = shift;

    my $nodeName = $this->getWorkBaseName();
    my $inNumber = $this->getSourcesNumber();

    #### Fichier de configuration ####
    my $oNtConfFile = File::Spec->catfile($ROK4::JOINCACHE::Shell::ONTCONFDIR, "$nodeName.txt");
    
    if (! open CFGF, ">", $oNtConfFile ) {
        ERROR(sprintf "Impossible de creer le fichier $oNtConfFile, en écriture.");
        return FALSE;
    }

    #### Sorties ####

    my $line = File::Spec->catfile($this->getScript()->getTempDir(), $this->getWorkName("I"));
    
    # Pas de masque de sortie si on a juste une image : le masque a été lié symboliquement
    if ($this->getPyramid()->ownMasks() && $inNumber > 1) {
        $line .= " " . File::Spec->catfile($this->getScript->getTempDir(), $this->getWorkName("M"));
    }
    
    printf CFGF "$line\n";
    
    #### Entrées ####
    my $inTemplate = $this->getWorkName("*_*");

    # le même pour tout le monde, entrées et sorties
    my $imgCacheName = "";
    for (my $i = $inNumber - 1; $i >= 0; $i--) {
        # Les images sont dans l'ordre suivant : du dessus vers le dessous
        # Dans le fichier de configuration de overlayNtiff, elles doivent être dans l'autre sens, d'où la lecture depuis la fin.
        my $sourceImage = $this->getSource($i);

        my $inImgName = $this->getWorkName($i."_I");
        my $inImgPath = File::Spec->catfile($this->getScript()->getTempDir(), $inImgName);
        $this->{script}->write(sprintf "PullSlab %s/%s $inImgName\n", $sourceImage->{img}->[0], $sourceImage->{img}->[1]);
        $line = "$inImgPath";

        if (defined $sourceImage->{msk}) {
            my $inMskName = $this->getWorkName($i."_M");
            my $inMskPath = File::Spec->catfile($this->getScript->getTempDir, $inMskName);
            $this->{script}->write(sprintf "PullSlab %s/%s $inMskName\n", $sourceImage->{msk}->[0], $sourceImage->{msk}->[1]);
            $line .= " $inMskPath";
        }

        printf CFGF "$line\n";

        # le même pour tout le monde, entrées et sorties
        $imgCacheName = $sourceImage->{img}->[1];
    }

    close CFGF;

    $this->{script}->write("OverlayNtiff $nodeName.txt $inTemplate\n");

    # Final location writting
    my $outImgName = $this->getWorkName("I");
    $this->{script}->write("PushSlab $outImgName $imgCacheName");
    
    if ($this->getPyramid()->ownMasks()) {
        my $outMaskName = $this->getWorkName("M");
        my $mskCacheName = $this->{pyramid}->getSlabPath("MASK", $this->getLevel(), $this->getCol(), $this->getRow(), FALSE);
        $this->{script}->write(" $outMaskName $mskCacheName");
    }

    $this->{script}->write("\n\n");
    
    return TRUE;
}

1;
__END__