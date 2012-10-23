package Cinnamon::DSL;
use strict;
use warnings;
use Exporter::Lite;
use Cinnamon::Config;
use Cinnamon::Local;
use Cinnamon::Remote;
use Cinnamon::Logger;
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
    sudo_stream
    call
);

our $STDOUT = \*STDOUT;
our $STDERR = \*STDERR;

sub set ($$) {
    my ($name, $value) = @_;
    Cinnamon::Config::set $name => $value;
}

sub get ($@) {
    my ($name, @args) = @_;
    local $_ = undef;
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

sub call ($$@) {
    my ($task, $job, @args) = @_;
    
    log info => "call $task";
    my $task_def = Cinnamon::Config::get_task $task;
    die "Task |$task| is not defined" unless $task_def;
    $task_def->($job, @args);
}

sub remote (&$;%) {
    my ($code, $host, %args) = @_;

    my $user = $args{user} || get 'user';
    log info => 'ssh ' . (defined $user ? "$user\@$host" : $host);

    local $_ = Cinnamon::Remote->new(
        host => $host,
        user => $user,
    );

    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opt;
    $opt = shift @cmd if ref $cmd[0] eq 'HASH';

    my ($stdout, $stderr);
    my $result;

    my $is_remote = ref $_ eq 'Cinnamon::Remote';
    my $host = $is_remote ? $_->host : 'localhost';

    log info => sprintf "[%s :: executing] %s", $host, join(' ', @cmd);

    if (ref $_ eq 'Cinnamon::Remote') {
        $result = $_->execute($opt, @cmd);
    }
    else {
        $result = Cinnamon::Local->execute(@cmd);
    }

    return ($result->{stdout}, $result->{stderr});
}

sub run_stream (@) {
    my (@cmd) = @_;
    my $opt;
    $opt = shift @cmd if ref $cmd[0] eq 'HASH';
    #$opt->{tty} = 1 if not exists $opt->{tty} and -t $STDOUT;

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
    my $line_number = {};
    my $print = sub {
        my ($s, $handle) = @_;
        my $type = $handle eq 'stdout' ? 'info' : 'error';
        while ($s =~ s{([^\x0D\x0A]*)\x0D?\x0A}{}) {
            log $type => sprintf "[%s] %d: %s",
                $host, ++$line_number->{$_[1]}, $1;
        }
        if (length $s) {
            log $type => sprintf "[%s] %d: %s",
                $host, ++$line_number->{$_[1]}, $s;
        }

        # XXX Bug: line number counting does not work when line
        # boundary does not match with the boundary AnyEvent::Handle's
        # invocation of on_read gives.
    };
    $stdout = AnyEvent::Handle->new(
        fh => $result->{stdout},
        on_read => sub {
            $print->($_[0]->rbuf => 'stdout');
            substr($_[0]->{rbuf}, 0) = '';
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
            $print->($_[0]->rbuf => 'stderr');
            substr($_[0]->{rbuf}, 0) = '';
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
        log error => my $msg = sprintf "[%s] Status: %d", $host, $return;
        die "$msg\n";
    }
}

sub sudo_stream (@) {
    my (@cmd) = @_;
    my $opt = {};
    $opt = shift @cmd if ref $cmd[0] eq 'HASH';
    $opt->{sudo} = 1;
    $opt->{password} = Cinnamon::Config::get('keychain')
        ->get_password_as_cv($_->user)->recv;
    run_stream $opt, @cmd;
}

sub sudo (@) {
    my (@cmd) = @_;
    my $password = Cinnamon::Config::get('keychain')
        ->get_password_as_cv($_->user)->recv;
    run {sudo => 1, password => $password}, @cmd;
}

!!1;
