package B::Deobfuscate;
use strict;
use warnings;
use vars '$VERSION';
use base 'B::Deparse';
use B ();
use B::Keywords ();

# Some functions may require() YAML

$VERSION = '0.03';

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
    length $dict_file or return;
    my $dict_data;

    # slurp the entire dictionary at once
    open DICT, '<', $dict_file
        or die "Cannot open dictionary $dict_file: $!";
    read DICT, $dict_data, -s DICT;
    close DICT or die "Cannot close $dict_file: $!";

    my $k = $self->load_keywords;

    $p->{'unknown_dict_data'} =
        [ sort { length $a <=> length $b or $a cmp $b }
          grep { ! /\W/ and ! exists $k->{$_} }
          split /\n/, $dict_data ];
}


sub next_short_dict_symbol {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};

    my $sym = shift @{ $p->{'unknown_dict_data'} };
    push @{ $p->{'used_symbols'} }, $sym.
    return $sym;
}

sub next_long_dict_symbol {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};

    my $sym = pop @{ $p->{'unknown_dict_data'} };
    push @{ $p->{'used_symbols'} }, $sym;
    return $sym;
}

sub load_user_config {
    my $self = shift;
    my $p = $self->{+__PACKAGE__};
    my $config_file = $p->{'user_config'};
    defined $config_file and length $config_file or return;

    -f $config_file or die "Configuration file $config_file doesn't exist";

    require YAML;
    my $config = (YAML::LoadFile( $config_file ))[0];
    $p->{'globals_to_ignore'} = $config->{'globals_to_ignore'};
    $p->{'pad_symbols'} = $config->{'lexicals'};
    $p->{'gv_symbols'} = $config->{'globals'};
    defined $config->{'dictionary'} and
        $p->{'unknown_dict_file'} = $config->{'dictionary'};
    if (defined $config->{'global_regex'}) {
        my $r = $config->{'global_regex'};
        $p->{'global_regex'} = qr/$r/;
    }

    # Symbols that are listed with an undef value actually
    # just aren't renamed at all.
    for my $symt_nym (qw/pad gv/) {
        my $symt = $p->{"${symt_nym}_symbols"};
        for my $symt_key (keys %$symt) {
            not defined $symt->{$symt_key} and
                $symt->{$symt_key} = $symt_key;
        }
    }
}

sub gv_should_be_renamed {
    my $self = shift;
    my $name = shift;
    my $p = $self->{+__PACKAGE__};
    my $k = $p->{'keywords'};

    # Ignore keywords
    return if exists $k->{$name} or
              $name =~ m{\A[[:digit:]]\z};

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

    $name =~ m{\A(\W+)} or die "Invalid pad variable name $name";
    my $sigil = $1;

    my $dict = $p->{'pad_symbols'};
    return $dict->{$name} if exists $dict->{$name};

    $dict->{$name} = $name;
    return $dict->{$name} = lc $sigil . $self->next_short_dict_symbol;
}

sub rename_gv {
    my $self = shift;
    my $name = shift;
    my $p = $self->{+__PACKAGE__};

    return $name unless $self->gv_should_be_renamed( $name );

    my $dict = $p->{'gv_symbols'};
    return $dict->{$name} if exists $dict->{$name};
    return $dict->{$name} = ucfirst $self->next_long_dict_symbol;
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );
    my $p = $self->{+__PACKAGE__} = {};
    $p->{'unknown_dict_file'} = '/usr/share/dict/stop';
    $p->{'unknown_dict_data'} = undef;
    $p->{'user_config'} = undef;
    $p->{'gv_match'} = qw/\A[[:lower:][:digit:]_]+\z/;
    $p->{'pad_symbols'} = {};
    $p->{'gv_symbols'} = {};
    $p->{'output_yaml'} = 0;

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

sub compile {
    my(@args) = @_;
    return sub {
        my $source = '';
        my $self = B::Deobfuscate->new(@args);
        $self->stash_subs("main");
        $self->{'curcv'} = B::main_cv;
        $self->walk_sub(B::main_cv, B::main_start);
        $source .= join '', $self->print_protos;
        @{$self->{'subs_todo'}} =
          sort {$a->[0] <=> $b->[0]} @{$self->{'subs_todo'}};
        $source .= join '', $self->indent($self->deparse(B::main_root, 0)), "\n"
          unless B::Deparse::null B::main_root ;
        my @text;
        while (scalar(@{$self->{'subs_todo'}})) {
            push @text, $self->next_todo;
        }
        $source .= join '', $self->indent(join("", @text)), "\n" if @text;

        my $p = $self->{+__PACKAGE__};
        my %dump = ( lexicals => $p->{'pad_symbols'},
                     globals => $p->{'gv_symbols'},
                     dictionary => $p->{'unknown_dict_file'},
                     global_regex => $p->{'gv_match'} );

        if ($p->{'output_yaml'}) {
            require YAML;
            print YAML::Dump(\%dump, $source);
        }
        else {
            print $source;
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

__END__

=head1 NAME

B::Deobfuscate - Extension to B::Deparse for use in de-obfuscating source code

=head1 SYNOPSIS

  perl -MO=Deobfuscate,-csynthetic.yml,-y synthetic.pl

=head1 DESCRIPTION

B::Deobfuscate is a backend module for the Perl compiler that generates perl
source code, based on the internal compiled structure that perl itself
creates after parsing a program. It adds symbol renaming functions to the
B::Deparse module. An obfuscated program is already parsed and interpreted
correctly by the B::Deparse program. Unfortunately, if the obfuscation
involved variable renaming then the resulting program also has obfuscated
symbols.

This module takes the last step and fixes names like $z5223ed336 to be a word
from a dictionary. While the name still isn't meaningful it is at least easier
to distinguish and read. Here are two examples - one from B::Deparse and one
from B::Deobfuscate.

After B::Deparse:

  if (@z6a703c020a) {
      (my($z5a5fa8125d, $zcc158ad3e0) = File::Temp::tempfile('UNLINK', 1));
      print($z5a5fa8125d "=over 8\n\n");
      (print($z5a5fa8125d @z6a703c020a) or die((((q[Can't print ] . $zcc158ad3e0) . ': ') . $!)));
      print($z5a5fa8125d "=back\n");
      (close(*$z5a5fa8125d) or die((((q[Can't close ] . *$za5fa8125d) . ': ' . $!)));
      (@z8374cc586e = $zcc158ad3e0);
      ($z9e5935eea4 = 1);
  }

After B::Deobfuscate:

  if (@parenthesises) {
      (my($scrupulousity, $postprocesser) = File::Temp::tempfile('UNLINK', 1));
      print($scrupulousity "=over 8\n\n");
      (print($scrupulousity @parenthesises) or die((((q[Can't print ] . $postprocesser) . ': ') . $!)));
      print($scrupulousity "=back\n");
      (close(*$scrupulousity) or die((((q[Can't close ] . *$postprocesser) . ': ') . $!)));
      (@interruptable = $postprocesser);
      ($propagandaist = 1);
  }

You'll note that the only real difference is that instead of variable names
like $z9e5935eea4 you get $propagandist.

Please note that this module is mainly new and untested code and is
still under development, so it may change in the future.

=head1 OPTIONS

As with all compiler backend options, these must follow directly after
the '-MO=Deobfuscate', separated by a comma but not any white space.
All options defined in B::Deparse are supported here - see the B::Deparse
documentation page to see what options are provided and how to use them.

=over 4

=item B<-d>I<DICTIONARY>

Normally B::Deobfuscate reads the dictionary file at /usr/share/dict/stop. If
you would like to specify a different dictionary follow the -d parameter with
the path the file. The path may not have commas in it and only lines in the
dictionary that do not match /\W/ will be used. The entire dictionary will be
loaded into memory at once.

  -d/usr/share/dict/stop

=item B<-m>I<REGEX>

Supply a different regular expression for deciding which symbols to rename.
The default value is /\A[[:lower:][:digit:]_]+\z/. Your expression must be
delimited by the '/' characters and you may not use that character within the
expression. That shouldn't be an issue because '/' isn't valid in a symbol
name anyway.

  -a/\A[[:lower:][:digit:]_]+\z/

=item B<-y>

print two B<YAML> documents to STDOUT instead of the deparsed source code.
The first document is a configuration document suitable for use with the B<-c>
parameter. The second document is the deparsed source code. Use this feature
to generate a configuration document for further, iterative reverse engineering.

=item B<-c>I<FILENAME>

Supply a filename to a B<YAML> configuration file. Normally you would generate this
file by saving the results of the B<-y> parameter to a file. You can then edit the
file to provide your own names for symbols and not rely on the random symbol picker
in B<B::Deobfuscate>. You may create your own B<YAML> configuration file as well.

=back

=head1 CONFIGURATION FILE

The B::Deobfuscation symbol renamer can be controlled with by a configuration file.
Use of this feature requires the L<YAML> module be installed.

 dictionary: '/usr/share/dict/propernames'
 global_regex: '(?:)'
 globals:
   kSDsfDS: Slartibartfast
   HGFdsfds: Triantaphyllos
 lexicals:
   '$SdfSd': '$No'
   '$GsdDd': '$Ed'
   '$Ksdfs': '$Ji'

The following keys are recognized:

=over 4

=item B<dictionary>

This is a filename path to the operative dictionary.

 dictionary: /usr/share/dict/stop

=item B<global_regex>

This regular expression tests global symbols. Only symbols that match this
expression may be renamed. The default value is '\A[[:lower:][:digit:]_]\z/.
In perl, global symbols are independent of their sigil so the values being
tested are bare. Future versions of B::Deobfuscate may add the sigil to the
symbol name.

 global_regex: '\A[[:lower:][:digit:]_]\z'

=item B<globals>

This is a hash detailing symbol names as used in the original source and the
name used in the deobfuscated source. For example - if the original source
has a variable named @z12345 and you wish to rename all occurrances to 
@URLList then the hash would associate 'z12345' with 'URLList'. The dictionary
picker fills these values in automatically.

If you wish to prevent B::Deobfuscate from renaming a symbol then specify the
new value as '~' (which in YAML terms is undef).

 globals:
   catfile: ~
   opt_n: ~
   opt_t: ~
   opt_u: ~
   z1234567890: Postprocesser
   z2345678901: Constructable
   z3456789012: Photosynthesises
   z4567890123: Undiscriminate
   z5678901234: Parenthesises
   z6789012345: Animadvertion

=item B<lexicals>

Lexicals is a hash exactly like `globals' except that all the symbol names
include the sigil which doesn't currently happen for globals.

 lexicals:
   '$k1234567890': '$ivs'
   '$k2345678901': '$ehs'
   '$k3456789012': '$ans'
   '$k4567890123': '$ons'
   '$k5678901234': '$ofs'
   '$k6789012345': '$gos'
   '$k7890123456': '$dus'
   '$k8901234567': '$iis'
   '$k9012345678': '$ats'
   '$k0123456780': '$ets'

=back

=head1 AUTHOR

Joshua b. Jore <jjore@cpan.org>

=head1 SEE ALSO

L<B::Deparse>
L<http://www.perlmonks.org/index.pl?node_id=243011>
L<http://www.perlmonks.org/index.pl?node_id=244604>

=cut
