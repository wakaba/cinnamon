package Cinnamon::Task;
use strict;
use warnings;

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

1;
