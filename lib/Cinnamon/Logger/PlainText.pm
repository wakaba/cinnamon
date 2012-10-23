package Cinnamon::Logger::PlainText;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub log {
    print { $_[0]->{stdout} } $_[2] . "\n";
}

1;
