use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'         => 'B::Deobfuscate',
    'VERSION_FROM' => 'lib/B/Deobfuscate.pm',
    'PREREQ_PM'    => {

        # B
        # B::Deparse
        # Carp
        # Data::Postponed
        'B::Keywords' => '0.03',
        'YAML'        => '0'
    },
    'ABSTRACT_FROM' => 'lib/B/Deobfuscate.pod',
    'AUTHOR'        => 'Joshua ben Jore <jjore@cpan.org>',
);
