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
File: SourceImage.pm

Class: ROK4::PREGENERATION::SourceImage

(see libperlauto/ROK4_Core_SourceImage.png)

Define a data source, with georeferenced image directory.

Using:
    (start code)
    use ROK4::PREGENERATION::SourceImage;

    # SourceImage object creation
    my $objSourceImage = ROK4::PREGENERATION::SourceImage->new({
        directory => "/home/ign/DATA",
        srs => "EPSG:4326"
    });
    (end code)

Attributes:
    PATHIMG - string - Path to images directory.
    images - <ROK4::Core::GeoImage> array - Georeferenced images' ensemble, found in PATHIMG and subdirectories
    srs - string - SRS of the georeferenced images
    bestResImage - <ROK4::Core::GeoImage> - Best resolution image
    pixel - <ROK4::Core::Pixel> - Pixel components of all images, have to be same for each one.
    
=cut

################################################################################

package ROK4::PREGENERATION::SourceImage;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use List::Util qw(min max);

use File::Path qw(make_path);

use ROK4::Core::GeoImage;
use ROK4::Core::Pixel;


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

SourceImage constructor. Bless an instance.

Parameters (hash):
    directory - string - Path to images' directory, to analyze.
    srs - string - SRS of the georeferenced images
    
See also:
    <_init>, <computeSourceImage>
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
        srs => undef,
        #
        bestResImage => undef,
        #
        pixel => undef,
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($params));

    return undef if (! $this->computeSourceImage());

    return $this;
}

=begin nd
Function: _init

Checks and stores informations.

Parameters (hash):
    directory - string - Path to images' directory, to analyze.
    srs - string - SRS of the georeferenced images
    
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
Function: computeSourceImage

Detects all handled files in *PATHIMG* and subdirectories and creates a corresponding <GeoImage> object. Determines data's components and check them.

See also:
    <getListImages>, <GeoImage::computeInfo>
=cut
sub computeSourceImage {
    my $this = shift;

    my $search = {
        images => [],
    };

    if (! $this->getListImages($this->{PATHIMG}, $search)) {
        ERROR ("Cannot browse image directory !");
        return FALSE;
    }

    my @listGeoImagePath = @{$search->{images}};
    if (scalar @listGeoImagePath == 0) {
        ERROR ("No handled image found in ".$this->{PATHIMG});
        return FALSE;
    }

    my $badRefCtrl = 0;
    
    foreach my $filepath (@listGeoImagePath) {

        my $objGeoImage = ROK4::Core::GeoImage->new($filepath, $this->{srs});

        if (! defined $objGeoImage) {
            ERROR ("Can not load image source ('$filepath') !");
            return FALSE;
        }

        # On récupère les caractéristiques de l'image APRÈS traitement, car c'est sur ces images que nous allons travailler
        my $pix = $objGeoImage->getPixel();
        if (! defined $pix) {
            ERROR ("Can not read image pixel info ('$filepath') !");
            return FALSE;
        }

        if (! defined $this->{pixel}) {
            # we read the first image, components are empty. This first image will be the reference.
            $this->{pixel} = $pix;
        } else {
            # we have already values. We must have the same components for all images
            if (! $pix->equals($this->{pixel})) {
                ERROR ("All images must have same components. This image ('$filepath') is different !");
                return FALSE;
            }
        }

        if ($objGeoImage->getXmin() == 0  && $objGeoImage->getYmax() == 0) {
            $badRefCtrl++;
            if ($badRefCtrl>1){
                WARN (sprintf "More than one image are at 0,0 position. Probably lost of georef file (tfw,...) for file : %s", $filepath);
            }
        }

        if (! defined $this->{bestResImage} || $objGeoImage->getXres() < $this->{bestResImage}->getXres() 
                                            || $objGeoImage->getYres() < $this->{bestResImage}->getYres()) {
            $this->{bestResImage} = $objGeoImage;
        }

        push(@{$this->{images}}, $objGeoImage);
    }

    if (scalar(@{$this->{images}}) == 0) {
        ERROR (sprintf "Can not found image source in '%s' !",$this->{PATHIMG});
        return FALSE;
    }

    return TRUE;
}

=begin nd
Function: getListImages

Recursive method to browse a directory and list all handled file. Returns an hash containing the image file path's array.
| {
|     images => [...],
| };

Parameters (list):
    directory - string - Path to directory, to browse.
    search - hash - Hash reference, to store images' paths.
=cut  
sub getListImages {
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
            if (! $this->getListImages($entry, $search)) {
                return FALSE;
            }
        }

        # Si le fichier n'a pas l'extension TIFF, JP2, BIL, ZBIL ou PNG, on ne le traite pas
        next if ( $entry !~ /.*\.(tif|tiff)$/i && $entry !~ /.*\.(png)$/i && $entry !~ /.*\.(jp2)$/i && $entry !~ /.*\.(bil|zbil)$/i);

        # On a à faire à un fichier avec l'extension TIFF/PNG/JPEG2000/BIL, on l'ajoute au tableau
        push @{$search->{images}}, $entry;
    }

    return TRUE;
}

=begin nd
Function: computeBBox

Calculate extrem limits of images, in the source SRS.

Returns a double list : (xMin,yMin,xMax,yMax).
=cut
sub computeBBox {
    my $this = shift;

    my ($xmin,$ymin,$xmax,$ymax) = $this->{images}->[0]->getBBox();

    foreach my $objImage (@{$this->{images}}) {
        $xmin = min($xmin, $objImage->getXmin());
        $xmax = max($xmax, $objImage->getXmax());
        $ymin = min($ymin, $objImage->getYmin());
        $ymax = max($ymax, $objImage->getYmax());
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

# Function: getPixel
sub getPixel {
    my $this = shift;
    return $this->{pixel};
}

# Function: getBestResImage
sub getBestResImage {
    my $this = shift;
    return $this->{bestResImage};
}

# Function: getImages
sub getImages {
    my $this = shift;
    # copy !
    my @images;
    foreach (@{$this->{images}}) {
        push @images, $_;
    }
    return @images;
}

1;
__END__
