package Cinnamon::DSL;
use strict;
use warnings;
use Exporter::Lite;
use Cinnamon qw(CTX);
use Cinnamon::Remote;
use Cinnamon::Logger;
use Cinnamon::TaskDef;

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

push our @CARP_NOT, qw(Cinnamon::Config);

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

sub task ($$;$) {
    my ($task, $task_def, $args) = @_;

    Cinnamon::Config::set_task $task => $task_def, $args;
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
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    my $result = CTX->run_cmd(\@cmd, $opts);
    return defined wantarray ? ($result->{stdout}, $result->{stderr}, $result) : $result;
}

sub sudo (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    $opts->{sudo} = 1;
    unless (defined $opts->{password}) {
        $opts->{password} = CTX->keychain->get_password_as_cv($_->user)->recv;
    }
    return run $opts, @cmd;
}

# For backward compatibility
*run_stream = \&run;
*sudo_stream = \&sudo;

!!1;
