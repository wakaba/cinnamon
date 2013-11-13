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

sub _get_hosts {
    my $v = shift;
    if (not defined $v) {
        return ();
    } elsif (ref $v eq 'CODE') {
        return _get_hosts($v->());
    } elsif (ref $v eq 'ARRAY') {
        return map { _get_hosts($_) } @$v;
    } elsif (UNIVERSAL::can($v, 'to_a')) {
        return map { _get_hosts($_) } @{$v->to_a};
    } else {
        return $v;
    }
}

sub get_hosts {
    my ($self) = @_;
    my $hosts = $self->hosts;

    my $found = {};
    return [grep { not $found->{$_}++ } _get_hosts $hosts];
}

sub get_desc {
    my ($self) = @_;
    my $desc = $self->{args}->{desc};
    if (defined $desc and ref $desc eq 'CODE') {
        return $desc->();
    } else {
        unless (defined $desc) {
            my $code = $Cinnamon::Context::CTX->get_param('get_role_desc_for');
            $desc = $code->($self->name) if $code;
        }
        return $desc; # or undef
    }
}

sub info {
    my ($self) = @_;
    return +{
        hosts  => $self->get_hosts,
        params => $self->params,
    };
}

1;
