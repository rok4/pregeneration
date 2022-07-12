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
File: SourceWMS.pm

Class: ROK4::PREGENERATION::SourceWMS

Stores parameters and builds WMS request.

Attributes:
    URL - string -  Left part of a WMS request, before the *?*.
    FULLURL - string -  Entire URL, with parameters
    FORMAT - string - Downloaded image format. Default: "image/jpeg".
    PARAMETERS - string - Additionnal parameters, like STYLES. Optionnal
    LAYERS - string - Layer name to harvest, parameter *LAYERS* of a WMS request.
    min_size - integer - Used to remove too small harvested images (full of nodata), in bytes. Can be zero (no limit).
    max_width - integer - Max image's pixel width which will be harvested, can be undefined (no limit).
    max_height - integer - Max image's pixel height which will be harvested, can be undefined (no limit).

If *max_width* and *max_height* are not defined, images will be harvested all-in-one. If defined, requested image size have to be a multiple of this size.
=cut

################################################################################

package ROK4::PREGENERATION::SourceWMS;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;

use ROK4::Core::Array;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

SourceWMS constructor. Bless an instance.

See also:
    <_init>
=cut
sub new {
    my $class = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above) and pod documentation (bottom)
    my $this = {
        URL => undef,
        FULLURL => undef,
        PARAMETERS => undef,
        FORMAT => "image/jpeg",
        LAYERS => undef,
        min_size => 0,
        max_width => undef,
        max_height => undef
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($params));

    return $this;
}

=begin nd
Function: _init

Checks and stores attributes' values.
=cut
sub _init {
    my $this   = shift;
    my $params = shift;
    
    if (exists $params->{max_pixel_size}) {
        $this->{max_width} = $params->{max_pixel_size}->[0];
        $this->{max_height} = $params->{max_pixel_size}->[1];
    }
    
    if (exists $params->{min_bytes_size}) {
        $this->{min_size} = $params->{min_bytes_size};
    }

    # URL
    $this->{URL} = $params->{url};
    $this->{URL} =~ s/\?$//;

    $this->{FULLURL} = sprintf "%s?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap", $this->{URL};

    # LAYERS
    $this->{LAYERS} = $params->{layers};
    $this->{FULLURL} .= "&LAYERS=".$this->{LAYERS};

    # FORMAT
    if (exists $params->{format} ) {
        $this->{FORMAT} = $params->{format};
    }
    $this->{FULLURL} .= "&FORMAT=".$this->{FORMAT};

    # PARAMETERS
    if (exists $params->{query_parameters} ) {
        $this->{PARAMETERS} = $params->{query_parameters};
        $this->{FULLURL} .= "&".$this->{PARAMETERS};
    } else {
        $this->{FULLURL} .= "&STYLES=";
    }
    
    return TRUE;
}

####################################################################################################
#                               Group: Request methods                                             #
####################################################################################################


=begin nd
Function: getGetMapUrl
=cut
sub getGetMapUrl {
    my $this = shift;

    my $srs = shift;
    my $width = shift;
    my $height = shift;

    my $w = $width;
    if (defined $this->{max_width} && $this->{max_width} < $width) {$w = $this->{max_width};}
    my $h = $height;
    if (defined $this->{max_height} && $this->{max_height} < $height) {$h = $this->{max_height};}

    return sprintf "%s&CRS=%s&WIDTH=%s&HEIGHT=%s", $this->{FULLURL}, $srs, $w, $h;
}

=begin nd
Function: getBboxesList

Determine bboxes' list to harvest, according to slab size, harvesting's limits and coordinates system particluarities

Return:
    A string array, bboxes as string, empty array if failure
=cut
sub getBboxesList {
    my $this = shift;

    my $xmin = shift;
    my $ymin = shift;
    my $xmax = shift;
    my $ymax = shift;
    my $width = shift;
    my $height = shift;
    my $inversion = shift;
    
    my $imagePerWidth = 1;
    my $imagePerHeight = 1;
    
    # Ground size of an harvested image
    my $groundHeight = $xmax-$xmin;
    my $groundWidth = $ymax-$ymin;
    
    if (defined $this->{max_width} && $this->{max_width} < $width) {
        if ($width % $this->{max_width} != 0) {
            ERROR(sprintf "Max harvested width (%s) is not a divisor of the image's width (%s) in the request." , $this->{max_width}, $width);
            return ();
        }
        $imagePerWidth = int($width/$this->{max_width});
        $groundWidth /= $imagePerWidth;
    }
    
    if (defined $this->{max_height} && $this->{max_height} < $height) {
        if ($height % $this->{max_height} != 0) {
            ERROR(sprintf "Max harvested height (%s) is not a divisor of the image's height (%s) in the request." ,$this->{max_height}, $height);
            return ();
        }
        $imagePerHeight = int($height/$this->{max_height});
        $groundHeight /= $imagePerHeight;
    }
    
    my @bboxes;
    for (my $i = 0; $i < $imagePerHeight; $i++) {
        for (my $j = 0; $j < $imagePerWidth; $j++) {
            if ($inversion) {
                push(
                    @bboxes,
                    sprintf ("%s,%s,%s,%s",
                        $ymax-($i+1)*$groundHeight, $xmin+$j*$groundWidth,
                        $ymax-$i*$groundHeight, $xmin+($j+1)*$groundWidth
                    )
                )
            } else {
                push(
                    @bboxes,
                    sprintf ("%s,%s,%s,%s",
                        $xmin+$j*$groundWidth, $ymax-($i+1)*$groundHeight,
                        $xmin+($j+1)*$groundWidth, $ymax-$i*$groundHeight
                    )
                )
            }
        }
    }
    
    return ("$imagePerWidth $imagePerHeight", @bboxes);
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getMinSize
sub getMinSize {
    my $this = shift;
    return $this->{min_size};
}

# Function: getExtension
sub getExtension {
    my $this = shift;

    if ($this->{FORMAT} eq "image/png") {
        return "png";
    } elsif ($this->{FORMAT} eq "image/jpeg") {
        return "jpg";
    } else {
        return "tif";
    }
}


1;
__END__
