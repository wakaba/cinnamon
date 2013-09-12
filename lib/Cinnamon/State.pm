package Cinnamon::State;
use strict;
use warnings;
use Cinnamon::TaskResult;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub context {
    return $_[0]->{context};
}

sub hosts {
    return $_[0]->{hosts} || [];
}

sub args {
    return $_[0]->{args} || [];
}

sub create_result {
    my ($self, %args) = @_;
    return Cinnamon::TaskResult->new(
        failed => defined $args{failed} ? $args{failed} : !!@{$args{failed_hosts} or []},
        succeeded_hosts => $args{succeeded_hosts},
        failed_hosts => $args{failed_hosts},
    );
}

1;
