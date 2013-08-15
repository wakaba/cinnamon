package Cinnamon::Role;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub name {
    return $_[0]->{name};
}

sub hosts {
    return $_[0]->{hosts};
}

sub params {
    return $_[0]->{params} ||= {};
}

sub args {
    return $_[0]->{args} ||= {};
}

sub get_hosts {
    my ($self) = @_;
    my $hosts = $self->hosts;
    if (ref $hosts eq 'CODE') {
        return $hosts->();
    }
    return ref $hosts eq 'ARRAY' ? $hosts : [$hosts];
}

sub info {
    my ($self) = @_;
    return +{
        hosts  => $self->get_hosts,
        params => $self->params,
    };
}

1;
