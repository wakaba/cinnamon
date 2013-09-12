package Cinnamon::Remote;
use strict;
use warnings;
use Cinnamon::CommandExecutor;
push our @ISA, qw(Cinnamon::CommandExecutor);
use Net::OpenSSH;
use Cinnamon::Logger;

use AnyEvent;
use AnyEvent::Handle;
use POSIX;

use Cinnamon::Logger;
use Cinnamon::Logger::Channel;

sub connection {
    my $self = shift;
       $self->{connection} ||= Net::OpenSSH->new(
           $self->{host}, user => $self->{user}
       );
}

sub host { $_[0]->{host} }

sub execute {
    my ($self, $commands, $opts) = @_;
    my $host = $self->host || die "Host is not set";
    my $conn = $self->connection;

    if (defined $opts && $opts->{sudo}) {
        if (@$commands == 1 and $commands->[0] =~ m{[ &<>|()]}) {
            @$commands = ('sudo', -Sk, '--', 'sh', -c => @$commands);
        } elsif (@$commands == 1 and $commands->[0] eq '') {
            @$commands = ('sudo', '-Sk');
        } else {
            @$commands = ('sudo', '-Sk', '--', @$commands);
        }
    } else {
        if (@$commands == 1 and $commands->[0] =~ m{[ &<>|()]}) {
            @$commands = ('sh', -c => @$commands);
        }
    }

    {
        my $user = $self->user;
        $user = defined $user ? $user . '@' : '';
        log info => "[$user$host] \$ " . join ' ', @$commands;
    }

    my ($stdin, $stdout, $stderr, $pid) = $conn->open3({
        tty => $opts->{tty},
    }, @$commands) or die "open3 failed: " . $conn->error;

    if ($opts->{password}) {
        print $stdin "$opts->{password}\n";
    }

    my $cv = AnyEvent->condvar;
    my $exitcode;
    my ($fhout, $fherr);

    my $stdout_str = '';
    my $stderr_str = '';

    my $start_time = time;
    my $end = sub {
        undef $fhout;
        undef $fherr;
        waitpid $pid, 0;
        $exitcode = $?;
        $cv->send;
    };

    my $user = $self->user;
    $user = defined $user ? $user . '@' : '';
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

    my $sigs = {};
    $sigs->{TERM} = AE::signal TERM => sub {
        kill 'TERM', $pid;
        undef $sigs;
    };
    $sigs->{INT} = AE::signal INT => sub {
        kill 'INT', $pid;
        undef $sigs;
    };

    $cv->recv;
    undef $sigs;

    my $time = time - $start_time;
    if ($exitcode != 0 or $time > 1.0) {
        log error => my $msg = "Exit with status $exitcode ($time s)";
        die "$msg\n" if not $opts->{ignore_error} and $exitcode != 0;
    }

    +{
        stdout    => $stdout_str,
        stderr    => $stderr_str,
        has_error => $exitcode > 0,
        error     => $exitcode,
    };
}

!!1;
