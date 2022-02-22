#!/usr/bin/perl -w

use ExtUtils::MakeMaker;

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
    PREREQ_FATAL => 1,
    # ack -h "^use [A-Z]" ./ | cut -d' ' -f2 | grep -v -E "ROK4" | sed -r "s#;##" | sort | uniq | sed -r "s/(.+)/\"\1\" => 0,/"
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
        "POSIX" => 0
    }
);
