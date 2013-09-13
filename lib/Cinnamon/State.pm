package Cinnamon::State;
use strict;
use warnings;
use AnyEvent;
use Scalar::Util qw(weaken);
use Cinnamon::Logger;
use Cinnamon::TaskResult;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub context {
    return $_[0]->{context};
}

sub hosts {
    return $_[0]->{hosts} || [];
}

sub args {
    return $_[0]->{args} || [];
}

sub remote {
    my ($self, %args) = @_;
    return bless {%args, state => $self, remote => 1}, 'Cinnamon::State::RemoteOrLocal';
}

sub local {
    my ($self, %args) = @_;
    return bless {%args, state => $self, local => 1}, 'Cinnamon::State::RemoteOrLocal';
}

sub create_result {
    my ($self, %args) = @_;
    return Cinnamon::TaskResult->new(
        failed => defined $args{failed} ? $args{failed} : !!@{$args{failed_hosts} or []},
        succeeded_hosts => $args{succeeded_hosts},
        failed_hosts => $args{failed_hosts},
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
            log error => 'SIGTERM received';
            $self->process_terminate_handlers({signal_name => 'TERM'});
            undef $t;
        };
    };
    $self->{SIGINT} ||= AE::signal INT => sub {
        my $t; $t = AE::timer 0, 0, sub {
            log error => 'SIGINT received';
            $self->process_terminate_handlers({signal_name => 'INT'});
            undef $t;
        };
    };
    push @{$self->{terminate_handlers} ||= []}, $code;
}

sub remove_terminate_handler {
    my ($self, $code) = @_;
    $self->{terminate_handlers} = [grep { $_ ne $code } @{$self->{terminate_handlers} or []}];
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

package Cinnamon::State::RemoteOrLocal;

sub run_as_cv {
    my ($self, $commands, $opts) = @_;
    return $self->{state}->context->get_command_executor(%$self)
        ->execute_as_cv($self->{state}, $commands, $opts);
}

sub sudo_as_cv {
    my ($self, $commands, $opts) = @_;
    return $self->{state}->context->get_command_executor(%$self)
        ->execute_as_cv($self->{state}, $commands, {%{$opts || {}}, sudo => 1});
}

1;
