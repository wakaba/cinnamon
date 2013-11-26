package Cinnamon::DSL;
use strict;
use warnings;
use Carp qw(croak);
use Exporter::Lite;
use Cinnamon::TaskDef;

our @EXPORT = qw(
    in_task_process
    invoke_in_main_process

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

sub in_task_process () {
    return $Cinnamon::LocalContext->in_task_process;
}

sub invoke_in_main_process ($) {
    croak "Can't invoke in the main process" unless in_task_process;
    return $Cinnamon::LocalContext->invoke_in_main_process($_[0]);
}

sub set ($$) {
    my ($name, $value) = @_;
    $Cinnamon::LocalContext->set_param($name => $value);
}

sub set_default ($$) {
    my ($name, $value) = @_;
    $Cinnamon::LocalContext->set_param(@_)
        unless defined $Cinnamon::LocalContext->params->{$_[0]};
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
        $Cinnamon::LocalContext->clone_for_task([$host], \@args),
        #role => ...,
        onerror => sub { die "$_[0]\n" },
    );
    return $result->return_values->{$host}; # or undef
}

sub remote (&$;%) {
    my ($code, $host, %args) = @_;
    my $user = defined $args{user} ? length $args{user} ? $args{user} : undef
                                   : get 'user';
    undef $user unless defined $user and length $user;

    local $Cinnamon::LocalContext = $Cinnamon::LocalContext->clone_with_new_command_executor(
        remote => 1,
        host => $host,
        user => $user,
    );
    local $_ = $Cinnamon::LocalContext->command_executor;
    $code->($host);
}

sub run (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    my $cv = $Cinnamon::LocalContext->run_as_cv($commands, $opts);
    my $result = $cv->recv;
    die "Command failed\n" if $result->is_fatal_error;
    return wantarray ? ($result->{stdout}, $result->{stderr}, $result) : $result;
}

sub sudo (@) {
    my (@cmd) = @_;
    my $opts = ref $cmd[0] eq 'HASH' ? shift @cmd : {};
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    my $cv = $Cinnamon::LocalContext->sudo_as_cv($commands, $opts);
    my $result = $cv->recv;
    die "Command failed\n" if $result->is_fatal_error;
    return wantarray ? ($result->{stdout}, $result->{stderr}, $result) : $result;
}

sub get_operator_name {
    return $Cinnamon::LocalContext->operator_name;
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
