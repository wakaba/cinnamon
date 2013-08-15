package Cinnamon::Task;
use strict;
use warnings;

sub new {
    my $class = $_[0];
    return bless {@_}, $class;
}

sub name {
    return $_[0]->{name};
}

sub code {
    return $_[0]->{code};
}

1;
