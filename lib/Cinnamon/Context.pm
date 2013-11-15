package Cinnamon::Context;
use strict;
use warnings;
use Cinnamon::Task;
push our @ISA, qw(Cinnamon::Task);
use Carp qw(croak);
use Cinnamon::Role;
use Cinnamon::TaskResult;
use Cinnamon::CommandExecutor::Local;
use Cinnamon::CommandExecutor::Remote;

sub new {
    my $class = shift;
    return bless {@_, roles => {}, tasks => {}}, $class;
}

sub info {
    $_[0]->output_channel->print($_[1], newline => 1, class => 'info');
}
sub error {
    $_[0]->output_channel->print($_[1], newline => 1, class => 'error');
}

sub load_config ($$) {
    my ($self, $config) = @_;
    do {
        package Cinnamon::Context::_config_script;
        do $config;
    } || do {
        if ($@) {
            $self->error($@);
            exit 1;
        }

        if ($!) {
            $self->error($!);
            exit 1;
        }
    };
}

sub set_role {
    my ($self, $name, $hosts, $params, $args) = @_;
    $self->{roles}->{$name} = Cinnamon::Role->new(
        name => $name,
        hosts => $hosts,
        params => $params || {},
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
        pop @$path if @$path and $path->[-1] eq '';
    }

    my $value = $self;
    for (@$path) {
        return undef unless defined $value;
        my $tasks = $value->tasks or return undef;
        $value = $tasks->{$_};
    }

    return $value;
}

sub keychain {
    return $_[0]->{keychain};
}

sub output_channel {
    return $_[0]->{output_channel};
}

sub get_command_executor {
    my ($self, %args) = @_;
    if ($args{remote}) {
        my $host = $args{host};
        my $user = $args{user};
        return $self->{remote}->{$host}->{defined $user ? 'user=' . $user : ''} ||= do {
            $self->info('ssh ' . (defined $user ? "$user\@$host" : $host));
            Cinnamon::CommandExecutor::Remote->new(
                host => $host,
                user => $user,
                output_channel => $self->output_channel,
            );
        };
    } elsif ($args{local}) {
        return $self->{local} ||= do {
            return Cinnamon::CommandExecutor::Local->new(
                output_channel => $self->output_channel,
            );
        };
    } else {
        die "Neither |remote| or |local| is specified";
    }
}

sub operator_name {
    return $_[0]->{operator_name};
}

!!1;
