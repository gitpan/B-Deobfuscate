use Module::Build;

Module::Build->new(
    module_name => 'B::Deobfuscate',
    license     => 'gpl',
)->create_build_script;