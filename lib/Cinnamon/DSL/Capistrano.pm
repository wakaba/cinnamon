package Cinnamon::DSL::Capistrano;
use strict;
use warnings;
use Path::Class;
use Carp qw(croak);
use Cinnamon::DSL::Capistrano::Filter ();
use Exporter::Lite;

our @EXPORT;

push @EXPORT, qw(get);
sub get ($) {
    local $_ = undef;
    $Cinnamon::LocalContext->get_param($_[0]);
}

push @EXPORT, qw(set);
sub set ($$) {
    my ($name, $value) = @_;
    $Cinnamon::LocalContext->set_param($name => $value);
}

push @EXPORT, qw(getuname);
sub getuname () {
    return $Cinnamon::LocalContext->global->operator_name;
}

push @EXPORT, qw(load);
sub load ($) {
    if ($Cinnamon::LocalContext->{LoadHandlers}->{$_[0]}) {
        $Cinnamon::LocalContext->{LoadHandlers}->{$_[0]}->();
    } else {
        # XXX loop detection?
        my $recipe_f = file($_[0]); # XXX path resolution?
        if (defined $Cinnamon::DSL::Capistrano::BaseFileName) {
            $recipe_f = $recipe_f->absolute(file($Cinnamon::DSL::Capistrano::BaseFileName)->dir);
        }
        Cinnamon::DSL::Capistrano::Filter->convert_and_run({
            file_name => $recipe_f->stringify,
        }, $recipe_f->slurp);
    }
}

push @EXPORT, qw(set_load_handler);
sub set_load_handler ($$) {
    $Cinnamon::LocalContext->{LoadHandlers}->{$_[0]} = $_[1];
}

push @EXPORT, qw(after);
sub after ($$) {
    my ($task, $code) = @_;
    # XXX not implemented
}

push @EXPORT, qw(role);
sub role ($$;$) {
    my ($name, $hosts, $params) = @_;
    $Cinnamon::LocalContext->global->set_role($name, $hosts, $params);
}

sub set_role_alias {
    $Cinnamon::LocalContext->global->set_role_alias($_[1] => $_[2]);
}

push @EXPORT, qw(desc);
sub desc ($) {
    my $name = shift;
    $Cinnamon::LocalContext->{LastDesc} = $name;
}

our $Tasks = undef;
push @EXPORT, qw(namespace);
sub namespace ($$) {
    my ($name, $code) = @_;
    my $tasks = [];
    {
        local $Tasks = $tasks;
        $code->();
    }
    push @$tasks, {path => [], args => {
        desc => delete $Cinnamon::LocalContext->{LastDesc}, # or undef
    }};
    $_->{path} = [$name, @{$_->{path}}] for @$tasks;
    if ($Tasks) {
        push @$Tasks, @$tasks;
    } else {
        $Cinnamon::LocalContext->global->define_tasks($tasks);
    }
}

push @EXPORT, qw(task);
sub task ($$) {
    my ($name, $code) = @_;
    my $def = {path => [$name], code => $code, args => {
        desc => delete $Cinnamon::LocalContext->{LastDesc}, # or undef
    }};
    if ($Tasks) {
        push @$Tasks, $def;
    } else {
        $Cinnamon::LocalContext->global->define_tasks([$def]);
    }
}

push @EXPORT, qw(puts);
sub puts (@) {
    print @_, "\n";
}

sub get_remote (;%) {
    my %args = @_;
    my $user = get 'user';
    undef $user unless defined $user and length $user;
    my $exec = $Cinnamon::LocalContext->global->get_command_executor(
        remote => 1,
        host => $Cinnamon::LocalContext->hosts->[0],
        user => $user,
    );
    return $Cinnamon::LocalContext->clone_with_command_executor($exec);
}

push @EXPORT, qw(run stream capture);
sub run (@) {
    my (@cmd) = @_;
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    my $cv = get_remote->run_as_cv($commands);
    my $result = $cv->recv;
    die "Command failed\n" if $result->is_fatal_error;
}
*stream = \&run;
*capture = \&run;

push @EXPORT, qw(sudo);
sub sudo (@) {
    my (@cmd) = @_;
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    my $cv = get_remote->sudo_as_cv($commands);
    my $result = $cv->recv;
    die "Command failed\n" if $result->is_fatal_error;
}

push @EXPORT, qw(system);
sub system (@) {
    my (@cmd) = @_;
    my $commands = (@cmd == 1 and $cmd[0] =~ m{[ &<>|()]}) ? $cmd[0] :
        (@cmd == 1 and $cmd[0] eq '') ? [] : \@cmd;
    my $exec = $Cinnamon::LocalContext->global->get_command_executor(local => 1);
    my $local_context = $Cinnamon::LocalContext->clone_with_command_executor($exec);
    my $cv = $local_context->run_as_cv($commands);
    my $result = $cv->recv;
    die "Command failed\n" if $result->is_fatal_error;
}

push @EXPORT, qw(application);
sub application () {
    return get 'application';
}

push @EXPORT, qw(call);
sub call ($;@) {
    my ($task_path, $host, @args) = @_;
    croak "Host is not specified" unless defined $host;
    my $task = $Cinnamon::LocalContext->global->get_task($task_path)
        or croak "Task |$task_path| not found";
    my $user = get 'user';
    $task->run(
        $Cinnamon::LocalContext->clone_for_task([$host], \@args),
        #role => ...,
        onerror => sub { die "$_[0]\n" },
    );
    set user => $user;
}

sub chomp {
    my (undef, $s) = @_;
    CORE::chomp $s;
    return $s;
}

sub define_method {
    my ($class, $name, $code) = @_;
    no strict 'refs';
    *{'Cinnamon::DSL::Capistrano::Filter::converted::'.$name} = $code;
}

1;
