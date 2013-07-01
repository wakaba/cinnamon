package Cinnamon::DSL;
use strict;
use warnings;
use Exporter::Lite;
use Cinnamon::Config;
use Cinnamon::Local;
use Cinnamon::Remote;
use Cinnamon::Logger;
use Cinnamon::Logger::Channel;
use Cinnamon::TaskDef;
use AnyEvent;
use AnyEvent::Handle;
use POSIX;

our @EXPORT = qw(
    set
    set_default
    get
    role
    task
    taskdef

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

sub set_default ($$) {
    my ($name, $value) = @_;
    Cinnamon::Config::set_default $name => $value;
}

sub get ($@) {
    my ($name, @args) = @_;
    local $_ = undef;
    Cinnamon::Config::get $name, @args;
}

sub role ($$;$%) {
    my ($name, $hosts, $params, %args) = @_;
    $params ||= {};
    Cinnamon::Config::set_role $name => $hosts, $params, %args;
}

sub task ($$;%) {
    my ($task, $task_def) = @_;

    Cinnamon::Config::set_task $task => $task_def;
}

sub taskdef (&$) {
    return Cinnamon::TaskDef->new_from_code_and_args($_[0], $_[1]);
}

sub call ($$@) {
    my ($task, $job, @args) = @_;
    my $task_def = Cinnamon::Config::get_task $task;
    die "Task |$task| is not defined" unless $task_def;
    #my $task_desc = ref $task_def eq 'Cinnamon::TaskDef' ? $task_def->get_param('desc') : undef;
    log info => sprintf "call %s%s",
        $task, ''; #defined $task_desc ? " ($task_desc)" : '';
    $task_def->($job, @args);
}

sub remote (&$;%) {
    my ($code, $host, %args) = @_;

    my $user = defined $args{user} ? length $args{user} ? $args{user} : undef
                                   : get 'user';
    undef $user unless defined $user and length $user;
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

    my $user = $is_remote ? $_->user : undef;
    $user = defined $user ? $user . '@' : '';
    log info => "[$user$host] \$ " . join ' ', @cmd;

    if (ref $_ eq 'Cinnamon::Remote') {
        $result = $_->execute($opt, @cmd);
    }
    else {
        $result = Cinnamon::Local->execute(@cmd);
    }

    if ($result->{has_error}) {
        die sprintf "error status: %d", $result->{error};
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

    my $user = $_->user;
    $user = defined $user ? $user . '@' : '';
    log info => "[$user$host] \$ " . join ' ', @cmd;
    
    $result = $_->execute_with_stream($opt, @cmd);
    if ($result->{has_error}) {
        my $message = sprintf "%s: %s", $host, $result->{stderr}, join(' ', @cmd);
        die $message;
    }
    
    my $cv = AnyEvent->condvar;
    my $stdout;
    my $stderr;
    my $return;
    my $start_time = time;
    my $end = sub {
        undef $stdout;
        undef $stderr;
        waitpid $result->{pid}, 0;
        $return = $?;
        $cv->send;
    };
    my $out_logger = Cinnamon::Logger::Channel->new(
        type => 'info',
        label => "$user$host o",
    );
    my $err_logger = Cinnamon::Logger::Channel->new(
        type => 'error',
        label => "$user$host e",
    );
    my $print = $opt->{hide_output} ? sub { } : sub {
        my ($s, $handle) = @_;
        ($handle eq 'stdout' ? $out_logger : $err_logger)->print($s);
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
            log error => sprintf "[%s o] %s (%d)", $host, $message, $!
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
            log error => sprintf "[%s e] %s (%d)", $host, $message, $!
                unless $! == POSIX::EPIPE;
            undef $stderr;
            $end->() if not $stdout and not $stderr;
        },
    );

    my $sigs = {};
    $sigs->{TERM} = AE::signal TERM => sub {
        kill 'TERM', $result->{pid};
        undef $sigs;
    };
    $sigs->{INT} = AE::signal INT => sub {
        kill 'INT', $result->{pid};
        undef $sigs;
    };

    $cv->recv;
    undef $sigs;

    my $time = time - $start_time;
    if ($return != 0 or $time > 1.0) {
        log error => my $msg = "Exit with status $return ($time s)";
        die "$msg\n" if $return != 0;
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
    my $tty = Cinnamon::Config::get('tty');
    run {sudo => 1, password => $password, tty => !! $tty}, @cmd;
}

!!1;
