package Cinnamon::Context;
use strict;
use warnings;
use Carp qw(croak);
use Class::Load ();

use Cinnamon::Config;
use Cinnamon::Logger;
use Cinnamon::Role;
use Cinnamon::Task::Cinnamon;

our $CTX;

sub new {
    my $class = shift;
    bless { }, $class;
}

sub run {
    my ($self, $role, $task, %opts)  = @_;
    Cinnamon::Logger->init_logger;

    $role =~ s/^\@// if defined $role;
    Cinnamon::Config::set role => $role;
    Cinnamon::Config::set task => $task;

    # XXX This should not be executed more than once by ./cin @role task1 task2
    Cinnamon::Config::load $role, $task, %opts;

    if ($opts{info}) {
        $self->dump_info;
        return ([], []);
    }

    my $args = $opts{args};
    my $hosts = my $orig_hosts = Cinnamon::Config::get_role;
    $hosts = $opts{hosts} if $opts{hosts};
    my $task_def = Cinnamon::Config::get_task;
    my $runner   = Cinnamon::Config::get('runner_class') || 'Cinnamon::Runner::Sequential';

    if (defined $task_def and ref $task_def eq 'HASH') {
        unshift @$args, $task;
        $task = 'cinnamon:task:list';
        Cinnamon::Config::set task => $task;
        $task_def = Cinnamon::Config::get_task;
    }

    if ($task eq 'cinnamon:role:hosts') {
        unshift @$args, $hosts || [];
        $hosts = [''];
    }

    unless (defined $orig_hosts) {
        if ($task =~ /^cinnamon:/) {
            $hosts ||= [''];
        } else {
            log 'error', "Role |\@$role| is not defined";
            return ([], ['undefined role']);
        }
    }
    unless (defined $task_def) {
        log 'error', "Task |$task| is not defined";
        return ([], ['undefined task']);
    }

    if (@$hosts == 0) {
        log error => "No host found for role '\@$role'";
    } elsif (@$hosts > 1 or $hosts->[0] ne '') {
        {
            my %found;
            $hosts = [grep { not $found{$_}++ } @$hosts];
        }

        my $desc = Cinnamon::Config::get_role_desc $role;
        log info => sprintf 'Host%s %s (@%s%s)',
            @$hosts == 1 ? '' : 's', (join ', ', @$hosts), $role,
            defined $desc ? ' ' . $desc : '';
        my $task_desc = ref $task_def eq 'Cinnamon::TaskDef' ? $task_def->get_param('desc') : undef;
        log info => sprintf 'call %s%s',
            $task, defined $task_desc ? " ($task_desc)" : '';
    }

    Class::Load::load_class $runner;

    my $result = Cinnamon::Config::with_local_config {
        $runner->start($hosts, $task_def, @$args);
    };
    my (@success, @error);
    
    for my $key (keys %{$result || {}}) {
        if ($result->{$key}->{error}) {
            push @error, $key;
        }
        else {
            push @success, $key;
        }
    }

    log success => sprintf(
        "\n========================\n[success]: %s",
        (join(', ', @success) || ''),
    );

    log error => sprintf(
        "[error]: %s",
        (join(', ', @error)   || ''),
    );

    return (\@success, \@error);
}

sub set_role {
    my ($self, $name, $hosts, $params, $args) = @_;
    $self->{roles}->{$name} = Cinnamon::Role->new(
        name => $name,
        hosts => $hosts,
        params => $params,
        args => $args,
    );
}

sub set_role_alias {
    my ($self, $n1 => $n2) = @_;
    $self->{roles}->{$n1} = $self->{roles}->{$n2} || croak "Role |$n2| is not defined";
}

sub get_role {
    my ($self, $name) = @_;
    return $self->{roles}->{$name}; # or undef
}

sub get_role_hosts {
    my ($self, $name) = @_;
    my $role = $self->{roles}->{$name} or return undef;
    my $hosts = $role->get_hosts;

    my $params = $role->params;
    for my $key (keys %$params) {
        Cinnamon::Config::set $key => $params->{$key};
    }

    return $hosts;
}

sub get_role_desc {
    my ($self, $name) = @_;
    my $desc = $self->{roles}->{$name}->get_desc;
    if (not defined $desc) {
        my $code = Cinnamon::Config::get 'get_role_desc_for';
        $desc = $code->($name) if $code;
    }
    return $desc;
}

sub roles {
    return $_[0]->{roles};
}

sub dump_info {
    my ($self) = @_;
    my $info = Cinnamon::Config::info;

    my $roles = $self->roles;
    my $role_info = {};
    for my $name (keys %$roles) {
        $role_info->{$name} = $roles->{$name}->info;
    }

    $info->{roles} = $role_info;
    require YAML;
    log 'info', YAML::Dump($info);
}

!!1;
