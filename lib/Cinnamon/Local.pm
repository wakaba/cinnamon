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

    # XXX $opts->{sudo};

    {
        my $host = $self->host;
        my $user = $self->user;
        $user = defined $user ? $user . '@' : '';
        log info => "[$user$host] \$ " . join ' ', @$commands;
    }

    # XXX $opts->{tty} $opts->{hide_output}
    # XXX async

    my $start_time = time;
    my $result = IPC::Run::run $commands, \my $stdin, \my $stdout, \my $stderr;
    my $exitcode = $?;
    chomp for ($stdout, $stderr);

    for my $line (split "\n", $stdout) {
        log info => sprintf "[localhost o] %s",
            $line;
    }
    for my $line (split "\n", $stderr) {
        log info => sprintf "[localhost e] %s",
            $line;
    }

    my $time = time - $start_time;
    if ($exitcode != 0 or $time > 1.0) {
        log error => my $msg = "Exit with status $exitcode ($time s)";
        die "$msg\n" if not $opts->{ignore_error} and $exitcode != 0;
    }

    return {
        stdout    => $stdout,
        stderr    => $stderr,
        has_error => $exitcode > 0,
        error     => $exitcode,
    };
}

!!1;
