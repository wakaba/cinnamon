package Cinnamon::DSL;
use strict;
use warnings;
use Carp qw(croak);
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

push our @CARP_NOT, qw(Cinnamon::Config Cinnamon::Task);

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
    my ($task_path, $host, @args) = @_;
    croak "Host is not specified" unless defined $host;
    my $task = CTX->get_task($task_path) or croak "Task |$task_path| not found";
    $task->run(
        hosts => [$host],
        args => \@args,
        onerror => sub { die "$_[0]\n" },
    );
}

sub remote (&$;%) {
    my ($code, $host, %args) = @_;
    my $user = defined $args{user} ? length $args{user} ? $args{user} : undef
                                   : get 'user';
    undef $user unless defined $user and length $user;

    local $_ = CTX->get_command_executor(
        remote => 1,
        host => $host,
        user => $user,
    );

    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    my $executor = (defined $_ and UNIVERSAL::isa($_, 'Cinnamon::Remote')) ? $_ : CTX->get_command_executor(local => 1);
    my $result = $executor->execute(\@cmd, $opts);
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
