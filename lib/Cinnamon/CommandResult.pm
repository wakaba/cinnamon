package Cinnamon::CommandResult;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub has_error {
    return $_[0]->{has_error};
}

sub error_code {
    return $_[0]->{error};
}

sub terminated_by_signal {
    return $_[0]->{terminated_by_signal};
}

sub elapsed_time {
    return $_[0]->{end_time} - $_[0]->{start_time};
}

1;
