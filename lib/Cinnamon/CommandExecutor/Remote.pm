package Cinnamon::CommandExecutor::Remote;
use strict;
use warnings;
use Cinnamon::CommandExecutor;
push our @ISA, qw(Cinnamon::CommandExecutor Cinnamon::Remote);
use Net::OpenSSH;
use Cinnamon::Logger;

use AnyEvent;
use AnyEvent::Handle;
use POSIX;
use Cinnamon::CommandResult;
use Cinnamon::Logger;
use Cinnamon::Logger::Channel;

sub connection {
    my $self = shift;
       $self->{connection} ||= Net::OpenSSH->new(
           $self->{host}, user => $self->{user}
       );
}

sub host { $_[0]->{host} || die "Host is not set" }

sub execute_as_cv {
    my ($self, $state, $commands, $opts) = @_;
    my $conn = $self->connection;
    my $cv = AE::cv;

    my $host = $self->host;
    my $user = $self->user;
    $user = defined $user ? $user . '@' : '';
    log info => "[$user$host] \$ " . join ' ', @$commands;

    my ($stdin, $stdout, $stderr, $pid) = $conn->open3({
        tty => $opts->{tty},
    }, @$commands) or die "open3 failed: " . $conn->error;

    my $signal_error;
    $state->add_terminate_handler(my $handler = sub {
        kill $_[0]->{signal_name}, $pid;
        $signal_error = 1;
        return {die => 0, remove => 1};
    });

    my ($fhout, $fherr);
    my $stdout_str = '';
    my $stderr_str = '';

    my $start_time = time;
    my $end = sub {
        undef $fhout;
        undef $fherr;
        waitpid $pid, 0;
        my $exitcode = $?;
        $state->remove_terminate_handler($handler);
        $cv->send(Cinnamon::CommandResult->new(
            start_time => $start_time,
            end_time => time,
            stdout    => $stdout_str,
            stderr    => $stderr_str,
            has_error => $exitcode > 0,
            error     => $exitcode,
            terminated_by_signal => $signal_error,
        ));
    };

    if ($opts->{password}) {
        print $stdin "$opts->{password}\n";
    }

    my $out_logger = Cinnamon::Logger::Channel->new(
        type => 'info',
        label => "$user$host o",
    );
    my $err_logger = Cinnamon::Logger::Channel->new(
        type => 'error',
        label => "$user$host e",
    );
    my $print = $opts->{hide_output} ? sub { } : sub {
        my ($s, $handle) = @_;
        ($handle eq 'stdout' ? $out_logger : $err_logger)->print($s);
    };

    $fhout = AnyEvent::Handle->new(
        fh => $stdout,
        on_read => sub {
            $stdout_str .= $_[0]->rbuf;
            $print->($_[0]->rbuf => 'stdout');
            substr($_[0]->{rbuf}, 0) = '';
        },
        on_eof => sub {
            undef $stdout;
            $end->() if not $stdout and not $stderr;
        },
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            log error => sprintf "[%s o]: %s (%d)", $host, $message, $!
                unless $! == POSIX::EPIPE;
            undef $stdout;
            $end->() if not $stdout and not $stderr;
        },
    );

    $fherr = AnyEvent::Handle->new(
        fh => $stderr,
        on_read => sub {
            $stderr_str .= $_[0]->rbuf;
            $print->($_[0]->rbuf => 'stderr');
            substr($_[0]->{rbuf}, 0) = '';
        },
        on_eof => sub {
            undef $stderr;
            $end->() if not $stdout and not $stderr;
        },
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            log error => sprintf "[%s e]: %s (%d)", $host, $message, $!
                unless $! == POSIX::EPIPE;
            undef $stderr;
            $end->() if not $stdout and not $stderr;
        },
    );

    return $cv;
}

# for backcompat
package Cinnamon::Remote;

!!1;
