use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME' => 'B::Deobfuscate',
    'VERSION_FROM' => 'lib/B/Deobfuscate.pm',
    'PREREQ_PM' => { 'B::Keywords' => 0,
                     'YAML'        => 0 },
    'ABSTRACT_FROM' => 'lib/B/Deobfuscate.pod',
    'AUTHOR' => 'Joshua b. Jore <jjore@cpan.org>',
);