package Cinnamon::CommandExecutor::Local;
use strict;
use warnings;
use Cinnamon::CommandExecutor;
push our @ISA, qw(Cinnamon::CommandExecutor);
use IPC::Run ();
use AnyEvent;
use Cinnamon::CommandResult;
use Cinnamon::Logger;

sub host { 'localhost' }

sub execute_as_cv {
    my ($self, $state, $commands, $opts) = @_;
    my $cv = AE::cv;

    my $host = $self->host;
    my $user = $self->user;
    $user = defined $user ? $user . '@' : '';
    log info => "[$user$host] \$ " . join ' ', @$commands;

    # XXX $opts->{tty} $opts->{hide_output}
    # XXX async

    my $start_time = time;
    my $result = IPC::Run::run $commands, \my $stdin, \my $stdout, \my $stderr;
    my $exitcode = $?;
    my $signal_error;
    chomp for ($stdout, $stderr);

    for my $line (split "\n", $stdout) {
        log info => sprintf "[localhost o] %s",
            $line;
    }
    for my $line (split "\n", $stderr) {
        log info => sprintf "[localhost e] %s",
            $line;
    }

    $cv->send(Cinnamon::CommandResult->new(
        start_time => $start_time,
        end_time => time,
        stdout    => $stdout,
        stderr    => $stderr,
        has_error => $exitcode > 0,
        error     => $exitcode,
        terminated_by_signal => $signal_error,
        opts => $opts,
    ));
    return $cv;
}

!!1;
