#!/usr/bin/perl -w

use ExtUtils::MakeMaker;

sub MY::postamble {
    return <<'ECHO_VERSION';
injectversion ::
	$(NOECHO) sed -i "s#@VERSION@#$(VERSION)#" $(INST_SCRIPT)/*.pl

ECHO_VERSION
}

WriteMakefile(
    # version du package complet
    NAME => "ROK4GENERATION",
    # install to INSTALL_BASE/bin
    EXE_FILES => [
        'bin/be4.pl',
        'bin/4alamo.pl',
        'bin/4head.pl',
        'bin/joincache.pl',
        'bin/pyr2pyr.pl'
    ],
    BUILD_REQUIRES => { 
        "ExtUtils::MakeMaker" => 0
    },
    # ack -h "^use [A-Z]" ./ | cut -d' ' -f2 | grep -v -E "ROK4::(BE4|FOURALAMO|FOURHEAD|JOINCACHE|PREGENERATION|PYR2PYR)" | sed -r "s#;##" | sort | uniq | sed -r "s/(.+)/\"\1\" => 0,/"
    PREREQ_PM   => {
        "Cwd" => 0,
        "Data::Dumper" => 0,
        "ExtUtils::MakeMaker" => 0,
        "File::Basename" => 0,
        "File::Path" => 0,
        "File::Spec" => 0,
        "FindBin" => 0,
        "Getopt::Long" => 0,
        "List::Util" => 0,
        "Log::Log4perl" => 0,
        "Math::BigFloat" => 0,
        "POSIX" => 0,
        "ROK4::Core::Array" => 0,
        "ROK4::Core::Base36" => 0,
        "ROK4::Core::Database" => 0,
        "ROK4::Core::GeoImage" => 0,
        "ROK4::Core::GeoVector" => 0,
        "ROK4::Core::LevelRaster" => 0,
        "ROK4::Core::Pixel" => 0,
        "ROK4::Core::ProxyGDAL" => 0,
        "ROK4::Core::ProxyPyramid" => 0,
        "ROK4::Core::ProxyStorage" => 0,
        "ROK4::Core::PyramidRaster" => 0,
        "ROK4::Core::PyramidVector" => 0,
        "ROK4::Core::Shell" => 0,
        "ROK4::Core::TileMatrix" => 0,
        "ROK4::Core::TileMatrixSet" => 0,
        "ROK4::Core::Utils" => 0,
    }
);
