use strict;
use warnings;
use Test::More tests => 65;
use File::Basename 'dirname';
use File::Spec::Functions qw( catfile catfile );

my $test_dir = dirname( $0 );

my @scripts =
    map catfile( $test_dir, "${_}_t"),
    qw(scalar array hash code glob);

my $syntax_checker = catfile( $test_dir, "syntax.pl" );

( my $perlbin = $^X ) =~ s/\\/\\\\/g;

for my $test (
              [ q["$syntax_checker" "$script"],
                'basic syntax'],
              [ q["-Mblib" "-MO=Deobfuscate" "$script"],
                'basic deobfuscation'],
              [ q["-Mblib" "-MO=Deobfuscate,-y" "$script"],
                'yaml output'],
              [ q["-Mblib" "-MO=Deobfuscate,-y" "$script" | "$perlbin" "-000" "-MYAML" "-e" "Load(scalar <>)"],
                'yaml syntax'],
              [ q["-Mblib" "-MO=Deobfuscate" "$script" | "$perlbin" "$syntax_checker"],
                'deobfuscation syntax check']
    ) {
    my $command   = $test->[0];
    my $test_name = $test->[1];

    for my $script (@scripts) {

	diag( eval qq{qq{"$perlbin" $command}} );
	local ( $@, $? );
        my $out = eval qq{qx["$perlbin" $command]};
	my ( $e, $rc ) = ( $@, $? >> 8 );
        is( $e, '', "$test_name eval" );
        is( $rc, 0, "$test_name exit code" );

        if ( $rc != 0 ) { print $out }
    }
}

my $canonizer = catfile( $test_dir, "canon.pl" );
for my $script (@scripts) {
    my $normal = qq["$perlbin" "-MO=Concise" "$script" | ] .
                 qq["$perlbin" "$canonizer"];
    my $deob   = qq["$perlbin" "-Mblib" "-MO=Deobfuscate" "$script" | ] .
                 qq["$perlbin" "-MO=Concise" | ] .
                 qq["$perlbin" "$canonizer"];

    $normal = `$normal`;
    is( $?, 0, "Fetching normal optree: $script" );

    $deob   = `$deob`;
    is( $?, 0, "Fetching deobfuscated optree: $script" );

    is( $normal eq $deob, "1", "Comparing optrees: $script" );
}
