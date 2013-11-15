package Cinnamon::CommandExecutor::InTaskProcess;
use strict;
use warnings;
use Cinnamon::CommandExecutor;
push our @ISA, qw(Cinnamon::CommandExecutor);

sub host {
    return $_[0]->{local} ? 'localhost' : $_[0]->{host} || die "Host is not set";
}

sub execute_as_cv {
    die "Not implemented";
}

sub as_args {
    return {
        remote => $_[0]->{remote},
        local => $_[0]->{local},
        host => $_[0]->{host},
        user => $_[0]->{user},
    };
}

1;
