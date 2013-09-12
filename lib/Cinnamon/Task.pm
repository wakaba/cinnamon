package Cinnamon::Task;
use strict;
use warnings;
use Carp qw(croak);
use Cinnamon::State;
use Cinnamon::Logger;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub name {
    return join ':', @{$_[0]->{path} or []};
}

sub code {
    if (@_ > 1) {
        $_[0]->{code} = $_[1];
    }
    return $_[0]->{code}; # or undef
}

sub is_callable {
    return !!$_[0]->{code};
}

sub tasks {
    return $_[0]->{tasks} ||= {};
}

sub has_subtasks {
    return !!(grep { $_ } values %{$_[0]->{tasks} or {}});
}

sub args {
    if (@_ > 1) {
        $_[0]->{args} = $_[1];
    }
    return $_[0]->{args}; # or undef
}

sub get_desc {
    my ($self) = @_;
    my $desc = $self->{args}->{desc};
    if (defined $desc and ref $desc eq 'CODE') {
        return $desc->();
    } else {
        return $desc; # or undef
    }
}

sub info {
    my ($self) = @_;
    return +{
        $self->name => $self->code,
    };
}

sub run {
    my ($self, %args) = @_;
    croak '|' . $self->name . '| is not callable' unless $self->is_callable;
    my $desc = $self->get_desc;
    log info => sprintf "call %s%s", $self->name, defined $desc ? " ($desc)" : '';

    my $hosts_option = $self->args->{hosts} || '';
    my $hosts;
    if ($hosts_option ne 'none') {
        ## At least one of |hosts| and |role| is required.
        $hosts = $args{hosts} || $args{role}->get_hosts;
        my %found;
        $hosts = [grep { not $found{$_}++ } @$hosts];
        my $desc = defined $args{role} ? $args{role}->get_desc : undef;
        log info => sprintf 'Host%s %s (@%s%s)',
            @$hosts == 1 ? '' : 's', (join ', ', @$hosts),
            $args{role}->name, defined $desc ? ' ' . $desc : '';
    } elsif (defined $args{role}) {
        my $desc = defined $args{role} ? $args{role}->get_desc : undef;
        log info => sprintf '(@%s%s)',
            $args{role}->name, defined $desc ? ' ' . $desc : '';
    }

    my $state = Cinnamon::State->new(
        context => $args{context},
        hosts => $hosts,
        args => $args{args},
    );
    if ($hosts_option eq 'all' or $hosts_option eq 'none') {
        my $result = eval { $self->code->($state) };
        
        if ($@) {
            chomp $@;
            my $msg = sprintf '%s %s', $self->name, $@;
            ($args{onerror} || sub { die $_[0] })->($msg);
            return $state->create_result(failed => 1);
        }
        return $result;
    } else {
        my @succeeded_host;
        my @failed_host;
        my $skip_by_error;
        for my $host (@{$state->hosts}) {
            if ($skip_by_error) {
                my $msg = sprintf '%s [%s] %s', $self->name, $host, 'Skipped';
                ($args{onerror} || sub { die $_[0] })->($msg);
                push @failed_host, $host;
                next;
            }
            
            local $Cinnamon::Runner::Host = $host; # XXX AE unsafe
            eval { $self->code->($host, @{$state->args}) };
            
            if ($@) {
                chomp $@;
                my $msg = sprintf '%s [%s] %s', $self->name, $host, $@;
                ($args{onerror} || sub { die $_[0] })->($msg);
                push @failed_host, $host;
                $skip_by_error = 1;
            } else {
                push @succeeded_host, $host;
            }
        }
        return $state->create_result(
            succeeded_hosts => \@succeeded_host,
            failed_hosts => \@failed_host,
        );
    }
}

1;
