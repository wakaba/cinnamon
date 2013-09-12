package Cinnamon::TaskResult;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub failed {
    return $_[0]->{failed};
}

sub succeeded_hosts {
    return $_[0]->{succeeded_hosts} || [];
}

sub failed_hosts {
    return $_[0]->{failed_hosts} || [];
}

1;
