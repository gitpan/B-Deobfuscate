package B::Deobfuscate;
use strict;
use warnings FATAL => 'all';
use base 'B::Deparse';
use B ();
use B::Keywords ();
use Carp 'confess';
use IO::Handle ();

# Some functions may require() YAML

our $VERSION = '0.09';

sub load_keywords {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};

    return $p->{'keywords'} = {
               map { $_, undef }
                   @B::Keywords::Barewords,
                   # Snip the sigils.
                   map(substr($_,1), @B::Keywords::Symbols) };
}

sub load_unknown_dict {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};
    my $dict_file = $p->{'unknown_dict_file'};

    local $/;
    my $dict_data;

    # slurp the entire dictionary at once
    if ($dict_file) {
        local *DICT;
        open DICT, '<', $dict_file
            or confess( "Cannot open dictionary $dict_file: $!" );
        $dict_data = <DICT>;
        close DICT or confess( "Cannot close $dict_file: $!" );
    } else {
        # Use the built-in symbol list
        $dict_data = <DATA>;
    }

    unless ($dict_data) {
	confess( "The symbol dictionary was empty!" );
    }

    my $k = $self->load_keywords;

    $p->{'unknown_dict_data'} =
        [ sort { length $a <=> length $b or $a cmp $b }
          grep { length > 3 and ! /\W/ and ! exists $k->{$_} }
          split /\n/, $dict_data ];
    
    unless (@{$p->{'unknown_dict_data'}}) {
	confess( "The symbol dictionary is empty!" );
    }
}


sub next_short_dict_symbol {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};

    my $sym = shift @{ $p->{'unknown_dict_data'} };
    push @{ $p->{'used_symbols'} }, $sym;
    
    unless ($sym) {
	confess( "The symbol dictionary has run out and is now empty" );
    }
    
    return $sym;
}

sub next_long_dict_symbol {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};

    my $sym = pop @{ $p->{'unknown_dict_data'} };
    push @{ $p->{'used_symbols'} }, $sym;

    unless ($sym) {
	confess( "The symbol dictionary has run out and is now empty" );
    }

    return $sym;
}

sub load_user_config {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};
    my $config_file = $p->{'user_config'};

    return unless $config_file;

    unless (-f $config_file) {
	confess( "Configuration file $config_file doesn't exist" );
    }

    require YAML;
    my $config = (YAML::LoadFile( $config_file ))[0];
    $p->{'globals_to_ignore'} = $config->{'globals_to_ignore'};
    $p->{'pad_symbols'} = $config->{'lexicals'};
    $p->{'gv_symbols'} = $config->{'globals'};
    $config->{'dictionary'} and
        $p->{'unknown_dict_file'} = $config->{'dictionary'};
    if ($config->{'global_regex'}) {
        $p->{'global_regex'} = qr/${\ $config->{'global_regex'}}/;
    }

    # Symbols that are listed with an undef value actually
    # just aren't renamed at all.
    for my $symt_nym (qw/pad gv/) {
        my $symt = $p->{"${symt_nym}_symbols"};
        for my $symt_key (keys %$symt) {
	    if (not defined $symt->{$symt_key}) {
		$symt->{$symt_key} = $symt_key;
	    }
        }
    }
}

sub gv_should_be_renamed {
    my $self = shift;
    my $sigil = shift;
    my $name = shift;
    my $p = $self->{+__PACKAGE__};
    my $k = $p->{'keywords'};

    confess( "Undefined sigil" ) unless defined $sigil;
    confess( "Undefined name" ) unless defined $name;

    # Ignore keywords
    return if
        exists $k->{$name} or
        "$sigil$name" =~ m{\A\$[[:digit:]]+\z};

    if (exists $p->{'gv_symbols'}{$name} or
        $name =~ $p->{'gv_match'} ) {
        return 1;
    }
    return;
}

sub rename_pad {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};
    my $name = shift;

    $name =~ m{\A(\W+)} or confess( "Invalid pad variable name $name" );
    my $sigil = $1;

    my $dict = $p->{'pad_symbols'};
    return $dict->{$name} if $dict->{$name};

#    $dict->{$name} = $name;
    $dict->{$name} = $sigil . $self->next_short_dict_symbol;
    
    unless ($dict->{$name}) {
	confess( "The suggested name for the lexical variable $name is empty" );
    }
    return $dict->{$name};
}

sub rename_gv {
    my $self = shift;
    my $name = shift;
    my $p = $self->{+__PACKAGE__};

    my $sigil_debug;
    my $sigil;
    FIND_SIGIL: {
	my $cx = 0;
	{
	    my $rv = (caller $cx)[3];
	    $sigil = ( $rv =~ /pp_rv2cv$/         ? '&'  :
		       $rv =~ /pp_gv$/            ? ''   :
		       $rv =~ /next_todo$/        ? ''   :
		       $rv =~ /pp_rv2hv$/         ? '%'  :
		       $rv =~ /pp_rv2gv$/         ? '*'  :
		       ($rv =~ /pp_gvsv$/ or
			$rv =~ /pp_rv2sv$/)       ? '$' :
		       ($rv =~ /pp_av2arylen$/ or
			$rv =~ /pp_aelemfast$/ or
			$rv =~ /pp_rv2av$/)       ? '@' :
		       undef );
	    $sigil_debug .= "$cx = $rv " .
		(defined $sigil ? "'$sigil'\n" : "\n");
	    
	    last FIND_SIGIL if defined $sigil;

	    $cx++;
	    unless ( (caller $cx)[3] ) {
		confess( "No sigil could be found. Please report the following text:\n$sigil_debug\n" );
	    }
	    redo;
	}
    }

    unless (defined $sigil) {
	confess( "No sigil could be found. Please report the following text:\n$sigil_debug\n" );
    }

    return $name unless $self->gv_should_be_renamed( $sigil, $name );

    my $dict = $p->{'gv_symbols'};
    
    my $sname = "$sigil$name";
    return $dict->{$sname} if exists $dict->{$sname};
    $dict->{$sname} = $self->next_long_dict_symbol;
    
    unless ($dict->{$sname}) {
	confess( "$sname could not be renamed." );
    }
    
    return $dict->{$sname};
}

## OVERRIDE METHODS FROM B::Deparse

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );
    my $p = $self->{+__PACKAGE__} = {};
    $p->{'unknown_dict_file'} = undef;
    $p->{'unknown_dict_data'} = undef;
    $p->{'user_config'} = undef;
    $p->{'gv_match'} = qw/\A[[:lower:][:digit:]_]+\z/;
    $p->{'pad_symbols'} = {};
    $p->{'gv_symbols'} = {};
    $p->{'output_yaml'} = 0;
    $p->{'output_fh'} = *STDOUT{IO};

    while (my $arg = shift @_) {
        if ($arg =~ m{\A-d([^,]+)}) {
            $p->{'unknown_dict_file'} = $1;
        } elsif ($arg =~ m{\A-c([^,]+)} ) {
            $p->{'user_config'} = $1;
        } elsif ($arg =~ m{\A-m/([^/]+)/} ) {
            $p->{'gv_match'} = $1;
        } elsif ($arg =~ m{\A-y}) {
            $p->{'output_yaml'} = 1;
        }
    }

    $self->load_user_config;
    $self->load_unknown_dict;

    return $self;
}

BEGIN {
    # B::perlstring was added in 5.8.0
    if ( *B::perlstring{CODE} ) {
	*perlstring = *B::perlstring{CODE};
    } else {
        *perlstring = sub { '"' . quotemeta( shift() ) . '"' };
    }
}

sub compile {
    my(@args) = @_;
    return sub {
        my $source = '';
        my $self = __PACKAGE__->new(@args);
	# First deparse command-line args
	if (defined $^I) { # deparse -i
	    $source .= q(BEGIN { $^I = ).perlstring($^I).qq(; }\n);
	}
        if ($^W) { # deparse -w
            $source .= qq(BEGIN { \$^W = $^W; }\n);
        }
        if ($/ ne "\n" or defined $O::savebackslash) { # deparse -l -0
            my $fs = perlstring($/) || 'undef';
            my $bs = perlstring($O::savebackslash) || 'undef';
            $source .= qq(BEGIN { \$/ = $fs; \$\\ = $bs; }\n);
        }
	
	# Remember - octal here
	if ($^V ge "\5\10\0") {
	    my @BEGINs = !( *B::begin_av{CODE} and
			    B::begin_av->isa('B::AV') ) ? () :
			    B::begin_av->ARRAY;
	    my @INITs  = B::init_av->isa('B::AV') ? B::init_av->ARRAY : ();
	    my @ENDs   = !( *B::end_av{CODE} and
			    B::end_av->isa('B::AV') ) ? () :
			    B::end_av->ARRAY;
	    for my $block (@BEGINs, @INITs, @ENDs) {
		$self->todo($block, 0);
	    }

	    $self->stash_subs;
	    $self->{'curcv'} = B::main_cv;
	    $self->{'curcvlex'} = undef;
	} else {
	    # 5.6.x
	    $self->stash_subs('main');
	    $self->{'curcv'} = B::main_cv;
	    $self->walk_sub(B::main_cv, B::main_start);
	}
	
	$source .= join "\n", $self->print_protos;
	@{$self->{'subs_todo'}} =
	  sort {$a->[0] <=> $b->[0]} @{$self->{'subs_todo'}};
	$source .= join "\n",
	    $self->indent($self->deparse(B::main_root, 0)), "\n"
	    unless B::Deparse::null B::main_root ;
	my @text;
	while (scalar(@{$self->{'subs_todo'}})) {
	    push @text, $self->next_todo;
	}
	$source .= join "\n", $self->indent(join("", @text)), "\n" if @text;

	# Print __DATA__ section, if necessary
	no strict 'refs';
	my $laststash = defined $self->{'curcop'}
	    ? $self->{'curcop'}->stash->NAME : $self->{'curstash'};
	if (defined *{$laststash."::DATA"}) {
	    if (eof *{$laststash."::DATA"}) {
		# I think this only happens when using the module on itself.
		{
		    local $/ = "__DATA__\n";
		    seek *{$laststash."::DATA"}, 0, 0;
		    readline *{$laststash."::DATA"};
		}
	    }
	    
	    $source .= "__DATA__\n";
	    $source .= join '', readline(*{$laststash."::DATA"});
	}

        my $p = $self->{+__PACKAGE__};
        my %dump = ( lexicals => $p->{'pad_symbols'},
                     globals => $p->{'gv_symbols'},
                     dictionary => $p->{'unknown_dict_file'},
                     global_regex => $p->{'gv_match'} );

        if ($p->{'output_yaml'}) {
            require YAML;
	    $p->{'output_fh'}->print( YAML::Dump(\%dump, $source) );
        }
        else {
	    $p->{'output_fh'}->print( $source );
        }
    }
}

sub padname {
    my $self = shift;
    my $padname = $self->SUPER::padname( @_ );

    return $self->rename_pad( $padname );
}

sub gv_name {
    my $self = shift;
    my $gv_name = $self->SUPER::gv_name( @_ );

    return $self->rename_gv( $gv_name );
}

1;

# The following list of words is compiled from the PGP freeware source code
# in the file named clients/pgp/shared/pgpHashWords.c.

__DATA__
adroitness
adviser
aftermath
aggregate
alkali
almighty
amulet
amusement
antenna
applicant
Apollo
armistice
article
asteroid
Atlantic
atmosphere
autopsy
Babylon
backwater
barbecue
belowground
bifocals
bodyguard
bookseller
borderline
bottomless
Bradbury
bravado
Brazilian
breakaway
Burlington
businessman
butterfat
Camelot
candidate
cannonball
Capricorn
caravan
caretaker
celebrate
cellulose
certify
chambermaid
Cherokee
Chicago
clergyman
coherence
combustion
commando
company
component
concurrent
confidence
conformist
congregate
consensus
consulting
corporate
corrosion
councilman
crossover
crucifix
cumbersome
customer
Dakota
decadence
December
decimal
designing
detector
detergent
determine
dictator
dinosaur
direction
disable
disbelief
disruptive
distortion
document
embezzle
enchanting
enrollment
enterprise
equation
equipment
escapade
Eskimo
everyday
examine
existence
exodus
fascinate
filament
finicky
forever
fortitude
frequency
gadgetry
Galveston
getaway
glossary
gossamer
graduate
gravity
guitarist
hamburger
Hamilton
handiwork
hazardous
headwaters
hemisphere
hesitate
hideaway
holiness
hurricane
hydraulic
impartial
impetus
inception
indigo
inertia
infancy
inferno
informant
insincere
insurgent
integrate
intention
inventive
Istanbul
Jamaica
Jupiter
leprosy
letterhead
liberty
maritime
matchmaker
maverick
Medusa
megaton
microscope
microwave
midsummer
millionaire
miracle
misnomer
molasses
molecule
Montana
monument
mosquito
narrative
nebula
newsletter
Norwegian
October
Ohio
onlooker
opulent
Orlando
outfielder
Pacific
pandemic
Pandora
paperweight
paragon
paragraph
paramount
passenger
pedigree
Pegasus
penetrate
perceptive
performance
pharmacy
phonetic
photograph
pioneer
pocketful
politeness
positive
potato
processor
provincial
proximate
puberty
publisher
pyramid
quantity
racketeer
rebellion
recipe
recover
repellent
replica
reproduce
resistor
responsive
retraction
retrieval
retrospect
revenue
revival
revolver
sandalwood
sardonic
Saturday
savagery
scavenger
sensation
sociable
souvenir
specialist
speculate
stethoscope
stupendous
supportive
surrender
suspicious
sympathy
tambourine
telephone
therapist
tobacco
tolerance
tomorrow
torpedo
tradition
travesty
trombonist
truncated
typewriter
ultimate
undaunted
underfoot
unicorn
unify
universe
unravel
upcoming
vacancy
vagabond
vertigo
Virginia
visitor
vocalist
voyager
warranty
Waterloo
whimsical
Wichita
Wilmington
Wyoming
yesteryear
Yucatan
aardvark
absurd
accrue
acme
adrift
adult
afflict
ahead
aimless
Algol
allow
alone
ammo
ancient
apple
artist
assume
Athens
atlas
Aztec
baboon
backfield
backward
banjo
beaming
bedlamp
beehive
beeswax
befriend
Belfast
berserk
billiard
bison
blackjack
blockade
blowtorch
bluebird
bombast
bookshelf
brackish
breadline
breakup
brickyard
briefcase
Burbank
button
buzzard
cement
chairlift
chatter
checkup
chisel
choking
chopper
Christmas
clamshell
classic
classroom
cleanup
clockwork
cobra
commence
concert
cowbell
crackdown
cranky
crowfoot
crucial
crumpled
crusade
cubic
dashboard
deadbolt
deckhand
dogsled
dragnet
drainage
dreadful
drifter
dropper
drumbeat
drunken
Dupont
dwelling
eating
edict
egghead
eightball
endorse
endow
enlist
erase
escape
exceed
eyeglass
eyetooth
facial
fallout
flagpole
flatfoot
flytrap
fracture
framework
freedom
frighten
gazelle
Geiger
glitter
glucose
goggles
goldfish
gremlin
guidance
hamlet
highchair
hockey
indoors
indulge
inverse
involve
island
jawbone
keyboard
kickoff
kiwi
klaxon
locale
lockup
merit
minnow
miser
Mohawk
mural
music
necklace
Neptune
newborn
nightbird
Oakland
obtuse
offload
optic
orca
payday
peachy
pheasant
physique
playhouse
Pluto
preclude
prefer
preshrunk
printer
prowler
pupil
puppy
python
quadrant
quiver
quota
ragtime
ratchet
rebirth
reform
regain
reindeer
rematch
repay
retouch
revenge
reward
rhythm
ribcage
ringbolt
robust
rocker
ruffled
sailboat
sawdust
scallion
scenic
scorecard
Scotland
seabird
select
sentence
shadow
shamrock
showgirl
skullcap
skydive
slingshot
slowdown
snapline
snapshot
snowcap
snowslide
solo
southward
soybean
spaniel
spearhead
spellbind
spheroid
spigot
spindle
spyglass
stagehand
stagnate
stairway
standard
stapler
steamship
sterling
stockman
stopwatch
stormy
sugar
surmount
suspense
sweatband
swelter
tactics
talon
tapeworm
tempest
tiger
tissue
tonic
topmost
tracker
transit
trauma
treadmill
Trojan
trouble
tumor
tunnel
tycoon
uncut
unearth
unwind
uproot
upset
upshot
vapor
village
virus
Vulcan
waffle
wallet
watchword
wayside
willow
woodlark
Zulu
