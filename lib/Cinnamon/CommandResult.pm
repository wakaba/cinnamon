package Cinnamon::CommandResult;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub host {
    return $_[0]->{host};
}

sub user {
    return $_[0]->{user};
}

sub has_error {
    return $_[0]->{has_error};
}

sub is_fatal_error {
    return ((not $_[0]->{opts}->{ignore_error} and $_[0]->error_code != 0) or
            $_[0]->terminated_by_signal);
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

sub show_result_and_detect_error {
    my ($self, $context) = @_;
    my $time = $self->elapsed_time;
    if ($self->error_code != 0 or $time > 1.0) {
        $context->error(my $msg = "[@{[$self->host]}] Exit with status @{[$self->error_code]} ($time s)");
        return $msg if $self->is_fatal_error;
    }
    return undef;
}

sub recv {
    return $_[0];
}

1;
