%close = ( '(' => '\\)',
           '[' => ']' );

undef $/;
$_=<>;
s/^\S+//gm;
s/^.+ex-.+\n//gm;
1 while s/([[(])(??{"[^$close{$^N}]+$close{$^N}"})//;
s/->\S+$//gm;
print
