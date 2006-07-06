#!perl
use Test;

if ( not $ENV{AUTHOR_TESTS} ) {
    plan( tests => 1 );
    skip( "Skipping author tests", 1 );
    exit;
}

require Test::Perl::Critic;
Test::Perl::Critic->import;
all_critic_ok();
