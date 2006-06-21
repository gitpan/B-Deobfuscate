use strict;
use warnings;
use Test::More tests => 65;
use File::Basename;
use File::Spec::Functions;

my $test_dir = dirname( $0 );

my @scripts =
    map catfile( $test_dir, "${_}_t"),
    qw(scalar array hash code glob);

my $syntax_checker = catfile( $test_dir, "syntax.pl" );

for my $test (
              [ q["$syntax_checker" "$script"],
                'basic syntax'],
              [ q["-Mblib" "-MO=Deobfuscate" "$script"],
                'basic deobfuscation'],
              [ q["-Mblib" "-MO=Deobfuscate,-y" "$script"],
                'yaml output'],
              [ q["-Mblib" "-MO=Deobfuscate,-y" "$script" | "$^X" "-000" "-MYAML" "-e" "Load(scalar <>)"],
                'yaml syntax'],
              [ q["-Mblib" "-MO=Deobfuscate" "$script" | "$^X" "$syntax_checker"],
                'deobfuscation syntax check']
    ) {
    my $command   = $test->[0];
    my $test_name = $test->[1];

    for my $script (@scripts) {

	diag( eval qq{qq{"$^X" $command}} );
        eval qq{qx["$^X" $command]};
        is( $@, '', "$test_name eval" );
        is( $? >> 8, 0,  $test_name );
    }
}

my $canonizer = catfile( $test_dir, "canon.pl" );
for my $script (@scripts) {
    my $normal = qq["$^X" "-MO=Concise" "$script" | ] .
                 qq["$^X" "$canonizer"];
    my $deob   = qq["$^X" "-Mblib" "-MO=Deobfuscate" "$script" | ] .
                 qq["$^X" "-MO=Concise" | ] .
                 qq["$^X" "$canonizer"];

    $normal = `$normal`;
    is( $?, 0, "Fetching normal optree: $script" );

    $deob   = `$deob`;
    is( $?, 0, "Fetching deobfuscated optree: $script" );

    is( $normal eq $deob, "1", "Comparing optrees: $script" );
}
