package Cinnamon::CommandExecutor;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub host { die "|host| not implemented" }
sub user { $_[0]->{user} } # or undef
sub output_channel { $_[0]->{output_channel} }

sub ui {
    if (@_ > 1) {
        $_[0]->{ui} = $_[1];
    }
    return $_[0]->{ui};
}

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

1;
