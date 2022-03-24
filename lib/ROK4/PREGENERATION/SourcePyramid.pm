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
File: SourcePyramid.pm

Class: ROK4::PREGENERATION::SourcePyramid

Define a data source, from pyramids' descriptors.

Using:
    (start code)
    use ROK4::PREGENERATION::SourcePyramid;
    (end code)

Attributes:
    pyramids - <ROK4::Core::RasterPyramid> array - Source pyramids
    
=cut

################################################################################

package ROK4::PREGENERATION::SourcePyramid;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use List::Util qw(min max);

use File::Path qw(make_path);

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

SourcePyramid constructor. Bless an instance.

Parameters (list):
    bottom - string - Bottom level identifiant, to check if pyramids own required levels
    top - string - Top level identifiant, to check if pyramids own required levels
    descriptors - array reference - Pyramids' descriptors
    
See also:
    <_init>
=cut
sub new {
    my $class = shift;
    my $bottom = shift;
    my $top = shift;
    my $descriptors = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        pyramids => []
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($bottom, $top, $descriptors));

    return $this;
}

=begin nd
Function: _init

Checks and stores informations.

Parameters (list):
    bottom - string - Bottom level identifiant, to check if pyramids own required levels
    top - string - Top level identifiant, to check if pyramids own required levels
    descriptors - array reference - Pyramids' descriptors
    
=cut
sub _init {
    my $this   = shift;
    my $bottom = shift;
    my $top = shift;
    my $descriptors = shift;

    # On charge toutes les pyramides (forcément raster pour le moment)

    my $pyramid = undef;
    foreach my $p (@{$descriptors}) {
        my $pyr = ROK4::Core::PyramidRaster->new("DESCRIPTOR", $p );
        if (! defined $pyr) {
            ERROR("Cannot load source pyramid $p");
            return FALSE;
        }
        # Toutes les pyramides doivent être "égales" au sein d'une source PYRAMIDS
        if (! defined $pyramid) {
            $pyramid = $pyr;
        } elsif ($pyramid->checkCompatibility($pyr) == 0) {
            ERROR("All pyramids in a PYRAMIDS source have to be \"equals\" (storage, pixel, TMS...) : the $p one is different)");
            return FALSE;
        }

        # La pyramide doit contenir tous les niveaux entre le haut et le bas
        if (! $pyr->ownLevels($bottom, $top)) {
            ERROR("Source pyramid $p does not own all levels between $bottom and $top");
            return FALSE;
        }

        push( @{$this->{pyramids}}, $pyr );
    }

    return TRUE;

}


####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getSRS
sub getSRS {
    my $this = shift;
    return $this->{pyramids}->[0]->getTileMatrixSet()->getSRS();
}


=begin nd
Function: getPixel

Pixel is returned only if all pyramids own the same. undef otherwise
=cut
sub getPixel {
    my $this = shift;

    my $pixel = undef;
    foreach my $p (@{$this->{pyramids}}) {
        if (! defined $pixel) {
            $pixel = $p->getPixel();
        } elsif (! $pixel->equals($p->getPixel())) {
            return undef;
        }
    }

    return $pixel;
}

# Function: getPyramids
sub getPyramids {
    my $this = shift;
    return $this->{pyramids};
}


1;
__END__
