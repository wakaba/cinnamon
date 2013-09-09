package Cinnamon::Local;
use strict;
use warnings;
use Cinnamon::CommandExecutor;
push our @ISA, qw(Cinnamon::CommandExecutor);
use IPC::Run ();
use Cinnamon::Logger;

sub host { 'localhost' }

sub execute {
    my ($self, $commands, $opts) = @_;

    # XXX $opts->{sudo} $opts->{tty} $opts->{hide_output}

    my $result = IPC::Run::run $commands, \my $stdin, \my $stdout, \my $stderr;
    chomp for ($stdout, $stderr);

    for my $line (split "\n", $stdout) {
        log info => sprintf "[localhost o] %s",
            $line;
    }
    for my $line (split "\n", $stderr) {
        log info => sprintf "[localhost e] %s",
            $line;
    }

    # XXX error / $opts->{ignore_errors}

    +{
        stdout    => $stdout,
        stderr    => $stderr,
        has_error => $? > 0,
        error     => $?,
    };
}

!!1;
