package Cinnamon::Context;
use strict;
use warnings;
use Cinnamon::Task;
push our @ISA, qw(Cinnamon::Task);
use Carp qw(croak);
use Cinnamon::Logger;
use Cinnamon::Role;

our $CTX;

sub new {
    my $class = shift;
    return bless {roles => {}, tasks => {}, params => {}}, $class;
}

sub run {
    my ($self, $role_name, $task_path, %opts)  = @_;

    $role_name =~ s/^\@// if defined $role_name;

    # XXX This should not be executed more than once by ./cin @role task1 task2
    $self->load_config($opts{config});

    if ($opts{info}) {
        $self->dump_info;
        return ([], []);
    }

    for my $key (keys %{ $opts{override_settings} or {} }) {
        $self->set_param($key => $opts{override_settings}->{$key});
    }

    my $args = $opts{args};
    my $hosts  = $self->get_role_hosts($role_name);
    my $orig_hosts = $hosts;
    $hosts = $opts{hosts} if $opts{hosts};
    my $show_tasklist;
    my $task = do {
        my $path = [split /:/, $task_path, -1];
        ($show_tasklist = 1, pop @$path) if @$path and $path->[-1] eq '';
        $self->get_task($path);
    };
    if (defined $task and ($show_tasklist or not $task->is_callable)) {
        unshift @$args, $task_path;
        require Cinnamon::Task::Cinnamon;
        $task_path = 'cinnamon:task:list';
        $task = $self->get_task([split /:/, $task_path]);
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
            log 'error', "Role |\@$role_name| is not defined";
            return ([], ['undefined role']);
        }
    }
    unless (defined $task) {
        log 'error', "Task |$task_path| is not defined";
        return ([], ['undefined task']);
    }

    if (@$hosts == 0) {
        log error => "No host found for role '\@$role_name'";
    } elsif (@$hosts > 1 or $hosts->[0] ne '') {
        {
            my %found;
            $hosts = [grep { not $found{$_}++ } @$hosts];
        }

        my $desc = $self->get_role_desc($role_name);
        log info => sprintf 'Host%s %s (@%s%s)',
            @$hosts == 1 ? '' : 's', (join ', ', @$hosts), $role_name,
            defined $desc ? ' ' . $desc : '';
        my $task_desc = $task->get_desc;
        log info => sprintf 'call %s%s',
            $task_path, defined $task_desc ? " ($task_desc)" : '';
    }

    my $runner = $self->get_param('runner_class') || 'Cinnamon::Runner::Sequential';
    eval qq{ require $runner } or die $@;

    $self->set_param(role => $role_name);
    $self->set_param(task => $task_path);

    my $result = do {
        local $self->{params} = {%{$self->{params}}};
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

    log info => "\n========================\n";
    if (@error) {
        log info => "[OK] @{[join ', ', @success]}";
        log error => "[NG] @{[join ', ', @error]}";
    } else {
        log success => "[OK] @{[join ', ', @success]}";
        log info => "[NG] @{[join ', ', @error]}";
    }

    return (\@success, \@error);
}

sub load_config ($$) {
    my $config = $_[1];
    do {
        package Cinnamon::Context::_config_script;
        do $config;
    } || do {
        if ($@) {
            log error => $@;
            exit 1;
        }

        if ($!) {
            log error => $!;
            exit 1;
        }
    };
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
        $self->set_param($key => $params->{$key});
    }

    return $hosts;
}

sub get_role_desc {
    my ($self, $name) = @_;
    my $desc = $self->{roles}->{$name}->get_desc;
    if (not defined $desc) {
        my $code = $self->get_param('get_role_desc_for');
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
    if (not ref $path) {
        $path = [split /:/, $path, -1];
        pop @$path if $path->[-1] eq '';
    }

    my $value = $self;
    for (@$path) {
        my $tasks = $value->tasks or return undef;
        $value = $tasks->{$_};
    }

    return $value;
}

sub params {
    return $_[0]->{params};
}

sub set_param {
    my ($self, $key, $value) = @_;
    $self->params->{$key} = $value;
}

sub get_param {
    my ($self, $key, @args) = @_;

    my $value = $self->params->{$key};
    $value = $value->(@args) if ref $value eq 'CODE';

    return $value;
}

sub keychain {
    return $_[0]->{keychain};
}

sub get_command_executor {
    my ($self, %args) = @_;
    if ($args{remote}) {
        my $host = $args{host};
        my $user = $args{user};
        return $self->{remote}->{$host}->{defined $user ? 'user=' . $user : ''} ||= do {
            log info => 'ssh ' . (defined $user ? "$user\@$host" : $host);
            Cinnamon::Remote->new(
                host => $host,
                user => $user,
            );
        };
    } elsif ($args{local}) {
        return $self->{local} ||= do {
            require Cinnamon::Local;
            return Cinnamon::Local->new;
        };
    } else {
        die "Neither |remote| or |local| is specified";
    }
}

sub dump_info {
    my ($self) = @_;

    my $roles = $self->roles;
    my $role_info = +{
        map { $_->name => $_->info } values %$roles,
    };

    my $tasks = $self->tasks;
    my $task_info = +{
        map { %{$_->info} } values %$tasks,
    };

    require YAML;
    log 'info', YAML::Dump({
        roles => $role_info,
        tasks => $task_info,
    });
}

!!1;
