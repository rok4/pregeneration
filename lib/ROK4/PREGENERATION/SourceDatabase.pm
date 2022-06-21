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
File: SourceDatabase.pm

Class: ROK4::PREGENERATION::SourceDatabase

Stores parameters about a data source in a PostgreSQL database.

Using:
    (start code)
    use ROK4::PREGENERATION::SourceDatabase;
    (end code)

Attributes:
    host - string - postgis server host
    port - integer - postgis server port
    dbname - string - postgis database name
    username - string - postgis server user
    password - string - postgis server user's password
    tables - hash - all informations about wanted tables
|        {
|            'public.departement' => {
|                'filter' => '',
|                'final_name' => 'departement',
|                'attributes' => {
|                    'ogc_fid' => {
|                        'max' => 101,
|                        'min' => 1,
|                        'count' => 101,
|                        'type' => 'integer'
|                    },
|                    'nom_dep' => {
|                        'type' => 'character varying(30)',
|                        'count' => 101
|                    },
|                    'insee_reg' => {
|                        'type' => 'character varying(2)',
|                        'values' => [
|                                        '75',
|                                        '06',
|                                        '24',
|                                        '03',
|                                        '01',
|                                        '28',
|                                        '52',
|                                        '93',
|                                        '04',
|                                        '94',
|                                        '02',
|                                        '44',
|                                        '53',
|                                        '27',
|                                        '11',
|                                        '32',
|                                        '76',
|                                        '84'
|                                    ],
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

package ROK4::PREGENERATION::SourceDatabase;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;

use ROK4::Core::Database;
use ROK4::Core::Array;


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

SourceDatabase constructor. Bless an instance.

Parameters (hash):
|        {
|          'srs' => 'EPSG:4326',
|          'db' => {
|                    'host' => 'localhost',
|                    'password' => 'reader',
|                    'database' => 'geodata',
|                    'user' => 'reader'
|                  },
|          'area' => {
|                      'bbox' => [
|                                  -5,
|                                  35,
|                                  10,
|                                  50
|                                ]
|                    },
|          'tables' => [
|                        {
|                          'schema' => 'essentiels',
|                          'attributes' => [
|                                            '*'
|                                          ],
|                          'native_name' => 'departement'
|                        },
|                        {
|                          'native_name' => 'region',
|                          'attributes' => [
|                                            '*'
|                                          ],
|                          'schema' => 'essentiels'
|                        }
|                      ],
|          'type' => 'POSTGRESQL'
|        }

See also:
    <_init>, <_load>
=cut
sub new {
    my $class = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above) and pod documentation (bottom)
    my $this = {
        host => undef,
        port => 5432,
        dbname => undef,
        username => undef,
        password => undef,
        tables => {}
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($params));
    return undef if (! $this->_load());

    return $this;
}

=begin nd
Function: _init

Checks and stores attributes' values.

Parameters (hash):
|        {
|          'srs' => 'EPSG:4326',
|          'db' => {
|                    'host' => 'localhost',
|                    'password' => 'reader',
|                    'database' => 'geodata',
|                    'user' => 'reader'
|                  },
|          'area' => {
|                      'bbox' => [
|                                  -5,
|                                  35,
|                                  10,
|                                  50
|                                ]
|                    },
|          'tables' => [
|                        {
|                          'schema' => 'essentiels',
|                          'attributes' => [
|                                            '*'
|                                          ],
|                          'native_name' => 'departement'
|                        },
|                        {
|                          'native_name' => 'region',
|                          'attributes' => [
|                                            '*'
|                                          ],
|                          'schema' => 'essentiels'
|                        }
|                      ],
|          'type' => 'POSTGRESQL'
|        }
=cut
sub _init {
    my $this   = shift;
    my $params = shift;
    
    # PORT    
    if (exists($params->{db}->{port}) && defined ($params->{db}->{port})) {
        $this->{port} = int($params->{db}->{port});
    }

    # Other parameters are mandatory
    # HOST
    $this->{host} = $params->{db}->{host};
    # DATABASE
    $this->{dbname} = $params->{db}->{database};
    # USERNAME
    $this->{username} = $params->{db}->{user};
    # PASSWORD
    $this->{password} = $params->{db}->{password};

    # TABLES
    foreach my $t (@{$params->{tables}}) {
        my $tab = {
            native_name => $t->{native_name},
            final_name => $t->{native_name},
            schema => "public",
            attributes => [],
            filter => ""
        };

        if (exists($t->{final_name})) {
            $tab->{final_name} = $t->{final_name};
        }

        if (exists($t->{schema})) {
            $tab->{schema} = $t->{schema};
        }

        if (exists($t->{attributes})) {
            $tab->{attributes} = $t->{attributes};
        }

        if (exists($t->{filter})) {
            $tab->{filter} = $t->{filter};
        }

        $this->{tables}->{sprintf ("%s.%s", $tab->{schema}, $tab->{native_name})} = $tab;
    }
    
    return TRUE;
}

=begin nd
Function: _load

Analyse tables and attributes connecting to the database
=cut
sub _load {
    my $this   = shift;

    my $database = ROK4::Core::Database->new(
        $this->{dbname},
        $this->{host},
        $this->{port},
        $this->{username},
        $this->{password}
    );

    if (! defined $database) {
        ERROR( "Cannot connect database to extract attributes and type for tables" );
        return FALSE;
    }

    while ( my ($table, $hash) = each(%{$this->{tables}})) {
        DEBUG("Récupération d'informations sur $table");
        if (! $database->is_table_exist($hash->{schema}, $hash->{native_name})) {
            ERROR("Table $table does not exist");
            return FALSE;
        }

        my ($geomname, $geomtype) = $database->get_geometry_column($hash->{schema}, $hash->{native_name});
        if (! defined $geomname) {
            ERROR("No geometry column in table $table");
            return FALSE;
        }

        $hash->{geometry} = {
            type => $geomtype,
            name => $geomname
        };

        my $native_atts = $database->get_attributes_hash($hash->{schema}, $hash->{native_name});
        
        if (scalar(@{$hash->{attributes}}) == 1 && $hash->{attributes}->[0] eq "*") {
            my @all = keys(%{$native_atts});
            $hash->{attributes} = \@all;
        }

        my $analysis = {};
        foreach my $a (@{$hash->{attributes}}) {
            if ($a eq "") {next;}

            if (! exists $native_atts->{$a}) {
                ERROR("Attribute $a is not present in table $table");
                return FALSE;
            }

            if ($a eq $geomname) {next;}

            $analysis->{$a} = {
                type => $native_atts->{$a}
            };

            my $count = $database->get_distinct_values_count($hash->{schema}, $hash->{native_name}, $a);
            if (! defined $count) {
                ERROR("Cannot get count of distinct value of attribute $a in table $table");
                return FALSE;
            }

            $analysis->{$a}->{count} = $count;

            my @numerics = ("integer", "real", "double precision", "numeric");
            if (defined ROK4::Core::Array::isInArray($native_atts->{$a}, @numerics)) {
                my ($min, $max) = $database->get_min_max_values($hash->{schema}, $hash->{native_name}, $a);
                if (defined $min) {
                    $analysis->{$a}->{min} = $min;
                    $analysis->{$a}->{max} = $max;
                }
            }

            elsif ($count <= 100) {
                my @distincts = $database->get_distinct_values($hash->{schema}, $hash->{native_name}, $a);
                $analysis->{$a}->{values} = \@distincts;
            }
        }
        $hash->{attributes} = $analysis;
    }

    $database->disconnect();

    return TRUE;
}

####################################################################################################
#                               Group: Request methods                                             #
####################################################################################################

=begin nd
Function: getInfos

Return database url ("host=postgis.ign.fr dbname=bdtopo user=ign password=PWD port=5432")
=cut
sub getInfos {
    my $this = shift;

    my $url = sprintf "host=%s dbname=%s user=%s password=%s port=%s",
        $this->{host}, $this->{dbname}, $this->{username}, $this->{password}, $this->{port};

    return $url;
}

=begin nd
Function: getSqlExports

Return a string array : SQL request and associated destination table name
=cut
sub getSqlExports {
    my $this = shift;

    my @sqls;

    while (my ($table, $hash) = each(%{$this->{tables}})) {

        my $sql = "";
        if (scalar(keys %{$hash->{attributes}}) != 0) {
            $sql = sprintf "SELECT %s,%s FROM $table", 
                join(",", keys(%{$hash->{attributes}})), 
                $hash->{geometry}->{name};
        } else {
            # Cas où l'on ne veut aucun attribut sauf la géométrie
            $sql = sprintf "SELECT %s FROM $table",
                $hash->{geometry}->{name};
        }
            
        if ($hash->{filter} ne "") {
            $sql .= sprintf " WHERE %s", $hash->{filter};
        }

        push(@sqls, $sql, $hash->{final_name});
    }

    return @sqls;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getTables
sub getTables {
    my $this = shift;
    return $this->{tables};
}

1;
__END__
