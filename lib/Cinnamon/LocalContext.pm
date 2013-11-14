package Cinnamon::LocalContext;
use strict;
use warnings;
use Scalar::Util qw(weaken);
use AnyEvent;
use Cinnamon::TaskResult;

sub new_from_global_context {
    return bless {global_context => $_[1]}, $_[0];
}

sub clone_for_task {
    return bless {
        %{$_[0]},
        command_executor => undef,
        hosts => $_[1],
        args => $_[2],
    }, ref $_[0];
}

sub clone_with_command_executor {
    return bless {%{$_[0]}, command_executor => $_[1]}, ref $_[0];
}

sub global {
    return $_[0]->{global_context};
}

sub command_executor {
    return $_[0]->{command_executor} ||= $_[0]->global->get_command_executor(local => 1);
}

sub keychain {
    return $_[0]->global->keychain;
}

sub get_password_as_cv {
    return $_[0]->keychain->get_password_as_cv($_[0]->command_executor->user);
}

sub run_as_cv {
    my ($self, $commands, $opts) = @_;
    my $cv = AE::cv;
    my $executor = $self->command_executor;
    $commands = $executor->construct_command($commands, $opts);
    $executor->execute_as_cv($self, $commands, $opts)->cb(sub {
        my $result = $_[0]->recv;
        $result->show_result_and_detect_error($self->global);
        $cv->send($result);
    });
    return $cv;
}

sub sudo_as_cv {
    my ($self, $commands, $opts) = @_;
    my $cv = AE::cv;
    $self->get_password_as_cv->cb(sub {
        $opts->{sudo} = 1;
        $opts->{password} = $_[0]->recv;
        $self->run_as_cv($commands, $opts)->cb(sub { $cv->send($_[0]->recv) });
    });
    return $cv;
}

sub output_channel {
    return $_[0]->global->output_channel;
}

sub get_param {
    my ($self, $name, @args) = @_;
    my $value = $self->global->params->{$name};
    $value = $self->eval(sub { $value->(@args) }) if ref $value eq 'CODE';
    return $value;
}

sub get_role_desc_by_name {
    my ($self, $role_name) = @_;
    my $code = $self->get_param('get_role_desc_for');
    return undef unless defined $code;
    return $self->eval(sub { $code->($role_name) });
}

sub eval {
    local $Cinnamon::LocalContext = $_[0];
    return $_[1]->();
}

sub hosts {
    return $_[0]->{hosts} || [];
}

sub args {
    return $_[0]->{args} || [];
}

sub create_result {
    my ($self, %args) = @_;
    return Cinnamon::TaskResult->new(
        failed => defined $args{failed} ? $args{failed} : !!@{$args{failed_hosts} or []},
        succeeded_hosts => $args{succeeded_hosts},
        failed_hosts => $args{failed_hosts},
        return_values => $args{return_values},
    );
}

sub create_result_cv {
    my $self = shift;
    return $self->create_result(@_)->as_cv;
}

sub add_terminate_handler {
    my ($self, $code) = @_;
    weaken ($self = $self);
    $self->{SIGTERM} ||= AE::signal TERM => sub {
        my $t; $t = AE::timer 0, 0, sub {
            $self->global->error('SIGTERM received');
            $self->process_terminate_handlers({signal_name => 'TERM'});
            undef $t;
        };
    };
    $self->{SIGINT} ||= AE::signal INT => sub {
        my $t; $t = AE::timer 0, 0, sub {
            $self->global->error('SIGINT received');
            $self->process_terminate_handlers({signal_name => 'INT'});
            undef $t;
        };
    };
    push @{$self->{terminate_handlers} ||= []}, $code;
}

sub remove_terminate_handler {
    my ($self, $code) = @_;
    $self->{terminate_handlers} = [grep { $_ ne $code } @{$self->{terminate_handlers} or []}];
    unless (@{$self->{terminate_handlers}}) {
        delete $self->{SIGTERM};
        delete $self->{SIGINT};
    }
}

sub process_terminate_handlers {
    my $self = shift;
    my $die;
    my @new;
    for (@{$self->{terminate_handlers} || []}) {
        my $result = $_->($_[0]);
        $die = 1 if $result->{die};
        push @new, $_ unless $result->{remove};
    }
    $self->{terminate_handlers} = \@new;
    die "Terminated by signal\n" if $die;
}

sub destroy {
    delete $_[0]->{SIGTERM};
    delete $_[0]->{SIGINT};
    delete $_[0]->{terminate_handlers};
}

# compat
*context = \&global;
sub remote {
    my ($self, %args) = @_;
    my $executor = $self->global->get_command_executor(%args, remote => 1);
    return $self->clone_with_command_executor($executor);
}
sub local {
    my ($self, %args) = @_;
    my $executor = $self->global->get_command_executor(%args, local => 1);
    return $self->clone_with_command_executor($executor);
}

1;