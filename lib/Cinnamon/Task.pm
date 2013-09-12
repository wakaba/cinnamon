package Cinnamon::Task;
use strict;
use warnings;
use Carp qw(croak);
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

    ## At least one of |hosts| and |role| is required.
    my $hosts = $args{hosts} || $args{role}->get_hosts;

    {
        my %found;
        $hosts = [grep { not $found{$_}++ } @$hosts];
    }
    {
        my $desc = defined $args{role} ? $args{role}->get_desc : undef;
        log info => sprintf 'Host%s %s (@%s%s)',
            @$hosts == 1 ? '' : 's', (join ', ', @$hosts),
            $args{role}->name, defined $desc ? ' ' . $desc : '';
    }

    # XXX
    if ($self->name eq 'cinnamon:role:hosts') {
        unshift @{$args{args} ||= []}, $hosts;
    }

    my %result;
    my $skip_by_error;
    for my $host (@$hosts) {
        if ($skip_by_error) {
            my $msg = sprintf '%s [%s] %s', $self->name, $host, 'Skipped';
            ($args{onerror} || sub { die $_[0] })->($msg);
            $result{$host}->{error}++;
            next;
        }
        
        $result{$host} = +{ error => 0 };
        
        local $Cinnamon::Runner::Host = $host; # XXX AE unsafe
        eval { $self->code->($host, @{$args{args} or []}) };
        
        if ($@) {
            chomp $@;
            my $msg = sprintf '%s [%s] %s', $self->name, $host, $@;
            ($args{onerror} || sub { die $_[0] })->($msg);
            $result{$host}->{error}++;
            $skip_by_error = 1;
        }
    }
    return \%result;
}

1;
