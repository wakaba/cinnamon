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

    get_operator_name

    log
);

push our @CARP_NOT, qw(Cinnamon::Task);

sub set ($$) {
    my ($name, $value) = @_;
    $Cinnamon::LocalContext->global->set_param($name => $value);
}

sub set_default ($$) {
    my ($name, $value) = @_;
    $Cinnamon::LocalContext->global->set_param(@_)
        unless defined $Cinnamon::LocalContext->global->params->{$_[0]};
}

sub get ($@) {
    my ($name, @args) = @_;
    local $_ = undef;
    $Cinnamon::LocalContext->get_param($name, @args);
}

sub role ($$;$%) {
    my ($name, $hosts, $params, %args) = @_;
    $Cinnamon::LocalContext->global->set_role($name, $hosts, $params, \%args);
}

sub _expand_tasks ($$$;$);
sub _expand_tasks ($$$;$) {
    my ($path, $task_def => $defs, $root_args) = @_;
    if (ref $task_def eq 'HASH') {
        push @$defs, {path => $path, args => $root_args};
        for (keys %$task_def) {
            _expand_tasks [@$path, $_], $task_def->{$_} => $defs;
        }
    } elsif (UNIVERSAL::isa($task_def, 'Cinnamon::TaskDef')) {
        push @$defs, {path => $path, code => $task_def->[0], args => $task_def->[1]};
    } else {
        push @$defs, {path => $path, code => $task_def, args => $root_args};
    }
}

sub task ($$;$) {
    my ($name, $task_def, $root_args) = @_;
    my $defs = [];
    $name = [$name] unless ref $name eq 'ARRAY';
    _expand_tasks $name => $task_def => $defs, $root_args;
    $Cinnamon::LocalContext->global->define_tasks($defs);
}

sub taskdef (&$) {
    return Cinnamon::TaskDef->new_from_code_and_args($_[0], $_[1]);
}

sub call ($$@) {
    my ($task_path, $host, @args) = @_;
    croak "Host is not specified" unless defined $host;
    my $task = $Cinnamon::LocalContext->global->get_task($task_path)
        or croak "Task |$task_path| not found";
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

    local $_ = $Cinnamon::LocalContext->global->get_command_executor(
        remote => 1,
        host => $host,
        user => $user,
    );
    local $Cinnamon::LocalContext = $Cinnamon::LocalContext->clone_with_command_executor($_);
    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    my $executor = $Cinnamon::LocalContext->command_executor;
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    $commands = $executor->construct_command($commands, $opts);
    my $cv = $executor->execute_as_cv($Cinnamon::LocalContext, $commands, $opts);
    my $result = $cv->recv;
    my $errmsg = $result->show_result_and_detect_error($Cinnamon::LocalContext->global);
    die "$errmsg\n" if defined $errmsg;
    return wantarray ? ($result->{stdout}, $result->{stderr}, $result) : $result;
}

sub sudo (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    $opts->{sudo} = 1;
    unless (defined $opts->{password}) {
        $opts->{password} = $Cinnamon::LocalContext->keychain->get_password_as_cv($Cinnamon::LocalContext->command_executor->user)->recv;
    }
    return run $opts, @cmd;
}

sub get_operator_name {
    return $Cinnamon::LocalContext->global->operator_name;
}

sub log ($$) {
    my ($type, $message) = @_;
    $Cinnamon::LocalContext->output_channel->print($message, newline => 1, class => $type);
    return;
}

# For backward compatibility
*run_stream = \&run;
*sudo_stream = \&sudo;
*Cinnamon::Logger::log = \&log;

!!1;
