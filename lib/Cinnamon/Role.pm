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
    my ($self, $get_code) = @_;
    my $desc = $self->{args}->{desc};
    if (defined $desc and ref $desc eq 'CODE') {
        return $desc->();
    } else {
        $desc = $get_code->($self->name) if not defined $desc and $get_code;
        return $desc; # or undef
    }
}

1;
