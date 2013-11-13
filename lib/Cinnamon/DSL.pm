package Cinnamon::DSL;
use strict;
use warnings;
use Carp qw(croak);
use Exporter::Lite;
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

    log
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
    my $task = $Cinnamon::Context::CTX->get_task($task_path) or croak "Task |$task_path| not found";
    my $result = $task->run(
        #role => ...,
        hosts => [$host],
        args => \@args,
        onerror => sub { die "$_[0]\n" },
    );
    return $result->return_values->{$host}; # or undef
}

sub remote (&$;%) {
    my ($code, $host, %args) = @_;
    my $user = defined $args{user} ? length $args{user} ? $args{user} : undef
                                   : get 'user';
    undef $user unless defined $user and length $user;

    local $_ = $Cinnamon::Context::CTX->get_command_executor(
        remote => 1,
        host => $host,
        user => $user,
    );

    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    my $executor = (defined $_ and UNIVERSAL::isa($_, 'Cinnamon::CommandExecutor::Remote')) ? $_ : $Cinnamon::Context::CTX->get_command_executor(local => 1);
    my $state = $Cinnamon::Runner::State; # XXX
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    $commands = $executor->construct_command($commands, $opts);
    my $cv = $executor->execute_as_cv($state, $commands, $opts);
    my $result = $cv->recv;
    my $errmsg = $result->show_result_and_detect_error($Cinnamon::Context::CTX);
    die "$errmsg\n" if defined $errmsg;
    return wantarray ? ($result->{stdout}, $result->{stderr}, $result) : $result;
}

sub sudo (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    $opts->{sudo} = 1;
    unless (defined $opts->{password}) {
        $opts->{password} = $Cinnamon::Context::CTX->keychain->get_password_as_cv($_->user)->recv;
    }
    return run $opts, @cmd;
}

sub log ($$) {
    my ($type, $message) = @_;
    $Cinnamon::Context::CTX->output_channel->print($message, newline => 1, class => $type);
    return;
}

# For backward compatibility
*run_stream = \&run;
*sudo_stream = \&sudo;
*Cinnamon::Logger::log = \&log;

!!1;
