package Cinnamon::Remote;
use strict;
use warnings;
use Net::OpenSSH;
use Cinnamon::Logger;

use AnyEvent;
use AnyEvent::Handle;
use POSIX;

use Cinnamon::Logger;
use Cinnamon::Logger::Channel;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub connection {
    my $self = shift;
       $self->{connection} ||= Net::OpenSSH->new(
           $self->{host}, user => $self->{user}
       );
}

sub host { $_[0]->{host} }

sub user { $_[0]->{user} }

sub execute {
    my ($self, @cmd) = @_;
    my $opt = shift @cmd;
    my $host = $self->host || '';
    my $conn = $self->connection;
    my $exec_opt = {};

    if (defined $opt && $opt->{sudo}) {
        @cmd = ('sudo', '-Sk', @cmd);
    }

    my ($stdin, $stdout, $stderr, $pid) = $conn->open_ex({
        stdin_pipe => 1,
        stdout_pipe => 1,
        stderr_pipe => 1,
        tty => $opt->{tty},
    }, join ' ', @cmd);

    if ($opt->{password}) {
        print $stdin "$opt->{password}\n";
    }

    my $cv = AnyEvent->condvar;
    my $exitcode;
    my ($fhout, $fherr);

    my $stdout_str = '';
    my $stderr_str = '';

    my $end = sub {
        undef $fhout;
        undef $fherr;
        waitpid $pid, 0;
        $exitcode = $?;
        $cv->send;
    };

    my $out_logger = Cinnamon::Logger::Channel->new(
        type => 'info',
        label => "$host o",
    );
    my $err_logger = Cinnamon::Logger::Channel->new(
        type => 'error',
        label => "$host e",
    );
    my $print = $opt->{hide_output} ? sub { } : sub {
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

    if ($exitcode != 0) {
        log error => my $msg = "Exit with status $exitcode";
        die "$msg\n";
    }

    +{
        stdout    => $stdout_str,
        stderr    => $stderr_str,
        has_error => !!$self->connection->error,
        error     => $self->connection->error,
    };
}

sub execute_with_stream {
    my ($self, @cmd) = @_;
    my $opt = shift @cmd;

    if (defined $opt && $opt->{sudo}) {
        if (@cmd == 1 and $cmd[0] =~ m{[ &<>|]}) {
            @cmd = ('sudo', -Sk, '--', 'sh', -c => @cmd);
        } else {
            @cmd = ('sudo', '-Sk', '--', @cmd);
        }
    } else {
        if (@cmd == 1 and $cmd[0] =~ m{[ &<>|]}) {
            @cmd = ('sh', -c => @cmd);
        }
    }

    my $command = join ' ', map { quotemeta } @cmd;
    #log info => $command;
    my ($stdin, $stdout, $stderr, $pid) = $self->connection->open_ex({
        stdin_pipe => 1,
        stdout_pipe => 1,
        stderr_pipe => 1,
        tty => $opt->{tty},
    }, $command);

    if (defined $opt && $opt->{sudo}) {
        print $stdin "$opt->{password}\n";
    }

    +{
        stdin     => $stdin,
        stdout    => $stdout,
        stderr    => $stderr,
        pid       => $pid,
        has_error => !!$self->connection->error,
        error     => $self->connection->error,
    };
}

sub DESTROY {
    my $self = shift;
       $self->{connection} = undef;
}

!!1;
