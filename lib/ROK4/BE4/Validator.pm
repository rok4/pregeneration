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
File: Validator.pm

Class: ROK4::BE4::Validator

Describe a node of a <ROK4::PREGENERATION::QTree> or a <ROK4::PREGENERATION::NNGraph>. Allow different storage (FileSystem, Ceph, Swift).

Using:
    (start code)
    use ROK4::BE4::Validator;

    if (! ROK4::BE4::Validator::validate()
    
    my $graph = ROK4::Core::Qtree->new(...)
    #or
    my $graph = ROK4::PREGENERATION::NNGraph->new(...)
    
    my $node = ROK4::BE4::Node->new({
        col => 51,
        row => 756,
        tm => $tm,
        graph => $graph
    });
    (end code)

=cut

################################################################################

package ROK4::BE4::Validator;

use strict;
use warnings;

use Log::Log4perl qw(:easy);

use File::Basename qw< dirname >;

use ROK4::Core::Utils ;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################

=begin nd
Constructor: validate

Parameters (hash):
    configuration - hash reference - configuration to validate

=cut
sub validate {
    my $configuration = shift;

    my $schema = ROK4::Core::Utils::get_hash_from_json_file(dirname(__FILE__)."/be4.schema.json");
    if (! defined $schema) {
        ERROR("Cannot load JSON schema file");
        return FALSE;
    }

    return ROK4::Core::Utils::validate_hash_with_json_schema($configuration, $schema);
}

1;
__END__