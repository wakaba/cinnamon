package Cinnamon::DSL;
use strict;
use warnings;
use parent qw(Exporter);

use Cinnamon::Config;
use Cinnamon::Local;
use Cinnamon::Remote;
use Cinnamon::Logger;
use Term::ReadKey;
use AnyEvent;
use AnyEvent::Handle;
use POSIX;

our @EXPORT = qw(
    set
    get
    role
    task

    remote
    run
    run_stream
    sudo
);

our $STDOUT = \*STDOUT;
our $STDERR = \*STDERR;

sub set ($$) {
    my ($name, $value) = @_;
    Cinnamon::Config::set $name => $value;
}

sub get ($@) {
    my ($name, @args) = @_;
    Cinnamon::Config::get $name, @args;
}

sub role ($$;$) {
    my ($name, $hosts, $params) = @_;
    $params ||= {};
    Cinnamon::Config::set_role $name => $hosts, $params;
}

sub task ($$) {
    my ($task, $task_def) = @_;

    Cinnamon::Config::set_task $task => $task_def;
}

sub remote (&$) {
    my ($code, $host) = @_;

    local $_ = Cinnamon::Remote->new(
        host => $host,
        user => Cinnamon::Config::user,
    );

    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opt;
    $opt = shift @cmd if ref $cmd[0] eq 'HASH';

    my ($stdout, $stderr);
    my $host;
    my $result;

    if (ref $_ eq 'Cinnamon::Remote') {
        $host   = $_->host;
        $result = $_->execute($opt, @cmd);
    }
    else {
        $host   = 'localhost';
        $result = Cinnamon::Local->execute(@cmd);
    }

    if ($result->{has_error}) {
        my $message = sprintf "%s: %s", $host, $result->{stderr}, join(' ', @cmd);
        die $message;
    }
    else {
        my $message = sprintf "[%s] %s: %s",
            $host, join(' ', @cmd), ($result->{stdout} || $result->{stderr});

        log info => $message;
    }

    return ($result->{stdout}, $result->{stderr});
}

sub run_stream (@) {
    my (@cmd) = @_;
    my $opt;
    $opt = shift @cmd if ref $cmd[0] eq 'HASH';
    $opt->{tty} = 1 if not exists $opt->{tty} and -t $STDOUT;

    unless (ref $_ eq 'Cinnamon::Remote') {
        die "Not implemented yet";
    }

    my $host = $_->host;
    my $result;

    my $message = sprintf "[%s] %s",
        $host, join ' ', @cmd;
    log info => $message;
    
    $result = $_->execute_with_stream($opt, @cmd);
    if ($result->{has_error}) {
        my $message = sprintf "%s: %s", $host, $result->{stderr}, join(' ', @cmd);
        die $message;
    }
    
    my $cv = AnyEvent->condvar;
    my $stdout;
    my $stderr;
    my $return;
    my $end = sub {
        undef $stdout;
        undef $stderr;
        waitpid $result->{pid}, 0;
        $return = $?;
        $cv->send;
    };
    $stdout = AnyEvent::Handle->new(
        fh => $result->{stdout},
        on_read => sub {
            print $STDOUT $_[0]->rbuf;
        },
        on_eof => sub {
            undef $stdout;
            $end->() if not $stdout and not $stderr;
        },
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            log error => sprintf "[%s] STDOUT: %s (%d)", $host, $message, $!
                unless $! == POSIX::EPIPE;
            undef $stdout;
            $end->() if not $stdout and not $stderr;
        },
    );
    $stderr = AnyEvent::Handle->new(
        fh => $result->{stderr},
        on_read => sub {
            print $STDERR $_[0]->rbuf;
        },
        on_eof => sub {
            undef $stderr;
            $end->() if not $stdout and not $stderr;
        },
        on_error => sub {
            my ($handle, $fatal, $message) = @_;
            log error => sprintf "[%s] STDERR: %s (%d)", $host, $message, $!
                unless $! == POSIX::EPIPE;
            undef $stderr;
            $end->() if not $stdout and not $stderr;
        },
    );

    $cv->recv;
    
    if ($return != 0) {
        log error => sprintf "[%s] Status: %d", $host, $return;
    }
}

sub sudo (@) {
    my (@cmd) = @_;

    my $password = Cinnamon::Config::get('password');
    unless (defined $password) {
        print "Enter sudo password: ";
        ReadMode "noecho";
        chomp($password = ReadLine 0);
        Cinnamon::Config::set('password' => $password);
    }

    run {sudo => 1, password => $password}, @cmd;
}

!!1;
