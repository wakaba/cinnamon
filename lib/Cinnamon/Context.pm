package Cinnamon::Context;
use strict;
use warnings;
use Cinnamon::Task;
push our @ISA, qw(Cinnamon::Task);
use Carp qw(croak);
use Class::Load ();
use Cinnamon::Config;
use Cinnamon::Logger;
use Cinnamon::Role;

our $CTX;

sub new {
    my $class = shift;
    return bless {roles => {}, tasks => {}}, $class;
}

sub run {
    my ($self, $role, $task_path, %opts)  = @_;
    Cinnamon::Logger->init_logger;

    $role =~ s/^\@// if defined $role;
    Cinnamon::Config::set role => $role;
    Cinnamon::Config::set task => $task_path;

    # XXX This should not be executed more than once by ./cin @role task1 task2
    Cinnamon::Config::load $role, $task_path, %opts;

    if ($opts{info}) {
        $self->dump_info;
        return ([], []);
    }

    my $args = $opts{args};
    my $hosts = my $orig_hosts = Cinnamon::Config::get_role;
    $hosts = $opts{hosts} if $opts{hosts};
    my $show_tasklist;
    my $task = do {
        my $path = [split /:/, $task_path, -1];
        ($show_tasklist = 1, pop @$path) if @$path and $path->[-1] eq '';
        $self->get_task($path);
    };
    my $runner   = Cinnamon::Config::get('runner_class') || 'Cinnamon::Runner::Sequential';
    if (defined $task and ($show_tasklist or not $task->is_callable)) {
        unshift @$args, $task_path;
        require Cinnamon::Task::Cinnamon;
        Cinnamon::Config::set task => $task_path = 'cinnamon:task:list';
        $task = $self->get_task(['cinnamon', 'task', 'list']);
    }

    if ($task_path eq 'cinnamon:role:hosts') {
        unshift @$args, $hosts || [];
        $hosts = [''];
        require Cinnamon::Task::Cinnamon;
    }

    unless (defined $orig_hosts) {
        if ($task_path =~ /^cinnamon:/) {
            $hosts ||= [''];
        } else {
            log 'error', "Role |\@$role| is not defined";
            return ([], ['undefined role']);
        }
    }
    unless (defined $task) {
        log 'error', "Task |$task_path| is not defined";
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
        my $task_desc = $task->get_desc;
        log info => sprintf 'call %s%s',
            $task_path, defined $task_desc ? " ($task_desc)" : '';
    }

    Class::Load::load_class $runner;

    my $result = Cinnamon::Config::with_local_config {
        $runner->start($hosts, $task, @$args);
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

*add_role = \&set_role; # compat

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

sub _task_def ($$);
sub _task_def ($$) {
    my ($name, $def) = @_;
    if (UNIVERSAL::isa($def, 'Cinnamon::TaskDef')) {
        return Cinnamon::Task->new(
            name => $name,
            code => $def->[0],
            args => $def->[1],
        );
    } elsif (ref $def eq 'HASH') {
        my $ts = Cinnamon::Task->new_task_set(
            name => $name,
        );
        for (keys %$def) {
            $ts->{tasks}->{$_} = _task_def $_, $def->{$_};
        }
        return $ts;
    } else {
        return Cinnamon::Task->new(
            name => $name,
            code => $def,
        );
    }
}

sub define_tasks {
    my ($self, $defs) = @_;
    for my $def (@$defs) {
        my $path = $def->{path};
        next unless @$path;

        my $obj = $self;
        for my $i (0..$#$path) {
            $obj->tasks->{$path->[$i]} ||= Cinnamon::Task->new(
                path => [@$path[0..$i]],
            );
            $obj = $obj->tasks->{$path->[$i]};
        }

        $obj->code($def->{code}) if $def->{code};
        $obj->args($def->{args}) if $def->{args} or $def->{code};
    }
}

sub get_task {
    my ($self, $path) = @_;

    my $value = $self;
    for (@$path) {
        my $tasks = $value->tasks or return undef;
        $value = $tasks->{$_};
    }

    return $value;
}

sub dump_info {
    my ($self) = @_;

    my $roles = $self->roles;
    my $role_info = +{
        map { $_->name => $_->info } values %$roles,
    };

    my $tasks = $self->tasks;
    my $task_info = +{
        map { $_->name => $_->code } values %$tasks,
    };

    require YAML;
    log 'info', YAML::Dump({
        roles => $role_info,
        tasks => $task_info,
    });
}

!!1;
