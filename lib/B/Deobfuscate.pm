package B::Deobfuscate;
use base 'B::Deparse';
use B qw(main_cv main_start main_root);

$VERSION = '0.01';

sub load_keyword_data {
    my $self = shift;
    $self->{'keyword_data'} =
        { map { $_ => undef } qw[NULL __FILE__ __LINE__ __PACKAGE__
__DATA__ __END__ AUTOLOAD BEGIN CORE DESTROY END EQ GE GT INIT LE LT NE
CHECK abs accept alarm and atan2 bind binmode bless caller chdir chmod chomp
chop chown chr chroot close closedir cmp connect continue cos crypt dbmclose
dbmopen defined delete die do dump each else elsif endgrent endhostent
endnetent endprotoent endpwent endservent eof eq eval exec exists exit exp
fcntl fileno flock for foreach fork format formline ge getc getgrent getgrgid
getgrnam gethostbyaddr gethostbyname gethostent getlogin getnetbyaddr
getnetbyname getnetent getpeername getpgrp getppid getpriority getprotobyname
getprotobynumber getprotoent getpwent getpwnam getpwuid getservbyname
getservbyport getservent getsockname getsockopt glob gmtime goto grep gt hex
if index int ioctl join keys kill last lc lcfirst le length link listen local
localtime lock log lstat lt m map mkdir msgctl msgget msgrcv msgsnd my ne next
no not oct open opendir or ord our pack package pipe pop pos print printf
prototype push q qq qr quotemeta qw qx rand read readdir readline readlink
readpipe recv redo ref rename require reset return reverse rewinddir rindex
rmdir s scalar seek seekdir select semctl semget semop send setgrent
sethostent setnetent setpgrp setpriority setprotoent setpwent setservent
setsockopt shift shmctl shmget shmread shmwrite shutdown sin sleep socket
socketpair sort splice split sprintf sqrt srand stat study sub substr symlink
syscall sysopen sysread sysseek system syswrite tell telldir tie tied time
times tr truncate uc ucfirst umask undef unless unlink unpack unshift untie
until use utime values vec wait waitpid wantarray warn while write x xor y]};
}

sub load_dict_data {
    my $self = shift;
    open DICT, '<', $self->{'dict_file'} or die "Cannot open dictionary at $self->{'dict_file'}: $!";
    read DICT, $self->{'dict_data'}, -s DICT;
    close DICT or die "Cannot close dictionary: $!";

    my $keys = $self->{'keyword_data'};
    $self->{'dict_data'} = [ sort { length $a <=> length $b }
                             grep { ! /\W/ and ! exists $keys->{$_} }
                             split /\n/,
                             $self->{'dict_data'} ];
}

sub rename_symbol {
    my $self = shift;
    my $name = shift;
    $name =~ $self->{'rename'};
}

sub read_dict_symbol {
    my $self = shift;
    $self->{'dict_data'} or $self->load_dict_data;

    return pop @{ $self->{'dict_data'} };
}

sub pad_unstunnix {
    my $self = shift;
    my $name = shift;
    my $dict = $self->{'pad_dict'};

    $name =~ m{^(\W+)} or die "Invalid pad variable name $name";
    my $sigil = $1;

    return $name unless $self->rename_symbol( $name );
    return $dict->{$name} if exists $dict->{$name};
    return $dict->{$name} = $sigil . $self->read_dict_symbol;
}

sub gv_unstunnix {
    my $self = shift;
    my $name = shift;
    my $dict = $self->{'gv_dict'};

    return $name unless $self->rename_symbol( $name );
    return $dict->{$name} if exists $dict->{$name};
    return $dict->{$name} = $self->read_dict_symbol;
}

sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );
    $self->load_keyword_data;
    $self->{'dict_file'} = '/usr/share/dict/stop';
    $self->{'dict_data'} = undef;
    $self->{'pad_dict'} = {};
    $self->{'gv_dict'} = {};
    $self->{'rename'} = qr/^\W{,2}z[\da-f]{8,}/;

    while (my $arg = shift @_) {
        if ($arg =~ /^-d([^,]+)/) {
            $self->{'dict_file'} = $1;
        } elsif ($arg =~ m{^-m/([^/]+)/} ) {
            $self->{'rename'} = $1;
        }
    }

    return $self;
}

sub compile {
    my(@args) = @_;
    return sub {
        my $self = B::Deobfuscate->new(@args);
        $self->stash_subs("main");
        $self->{'curcv'} = main_cv;
        $self->walk_sub(main_cv, main_start);
        print $self->print_protos;
        @{$self->{'subs_todo'}} =
          sort {$a->[0] <=> $b->[0]} @{$self->{'subs_todo'}};
        print $self->indent($self->deparse(main_root, 0)), "\n"
          unless B::Deparse::null main_root;
        my @text;
        while (scalar(@{$self->{'subs_todo'}})) {
            push @text, $self->next_todo;
        }
        print $self->indent(join("", @text)), "\n" if @text;
    }
}

sub padname {
    my $self = shift;
    my $padname = $self->SUPER::padname( @_ );

    return $self->pad_unstunnix( $padname );
}

sub gv_name {
    my $self = shift;
    my $gv_name = $self->SUPER::gv_name( @_ );

    return $self->gv_unstunnix( $gv_name );
}

1;

__END__

=head1 B::Deobfuscate

B::Deobfuscate - Extension to B::Deparse for use in de-obfuscating source code

=head1 SYNOPSIS

  perl -MO=Deobfuscate[,-d*DICTIONARY*][,-m*REGEX*] *prog.pl*

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
The default value is /^\W{,2}z[\da-f]{8,}/. Your expression must be delimited
by the '/' characters and you may not use that character within the expression.
That shouldn't be an issue because '/' isn't valid in a symbol name anyway.

  -a/^\W{,2}z[\da-f]{8,}/

=back

=head1 AUTHOR

Joshua b. Jore <jjore@cpan.org>

=head1 SEE ALSO

L<B::Deparse>
L<http://www.perlmonks.org/index.pl?node_id=243011>
L<http://www.perlmonks.org/index.pl?node_id=244604>

=cut
