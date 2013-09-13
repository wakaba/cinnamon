package Cinnamon::CommandExecutor;
use strict;
use warnings;
use Cinnamon::Logger;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub host { die "|host| not implemented" }
sub user { $_[0]->{user} } # or undef

sub construct_command {
    my ($self, $commands, $opts) = @_;
    if ($opts->{sudo}) {
        if (not ref $commands) {
            $commands = ['sudo', '-Sk', '--', 'sh', -c => $commands];
        } else {
            $commands = ['sudo', '-Sk', '--', @$commands];
        }
    } else {
        if (not ref $commands) {
            $commands = ['sh', -c => $commands];
        }
    }
    return $commands;
}

sub execute_as_cv { die "|execute_as_cv| not implemented" }

sub execute {
    my $self = shift;
    my $opts = $_[2];

    my $cv = $self->execute_as_cv(@_);
    my $result = $cv->recv;

    my $time = $result->elapsed_time;
    if ($result->error_code != 0 or $time > 1.0) {
        log error => my $msg = "Exit with status @{[$result->error_code]} ($time s)";
        die "$msg\n" if (not $opts->{ignore_error} and $result->error_code != 0) or $result->terminated_by_signal;
    }

    return $result;
}

1;
