use Module::Build;

Module::Build->new(
    module_name => 'B::Deobfuscate',
    license     => 'gpl',
    requires    => { B::Keywords => 0,
                     YAML        => 0 }
)->create_build_script;