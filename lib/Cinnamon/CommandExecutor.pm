package Cinnamon::CommandExecutor;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub host { die "|host| not implemented" }
sub user { $_[0]->{user} } # or undef

sub execute { die "|execute| not implemented" }

1;
