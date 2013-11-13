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

sub _get_hosts ($$);
sub _get_hosts ($$) {
    my ($v, $lc) = @_;
    if (not defined $v) {
        return ();
    } elsif (ref $v eq 'CODE') {
        return _get_hosts($lc->eval($v), $lc);
    } elsif (ref $v eq 'ARRAY') {
        return map { _get_hosts($_, $lc) } @$v;
    } elsif (UNIVERSAL::can($v, 'to_a')) {
        return map { _get_hosts($_, $lc) } @{$v->to_a};
    } else {
        return $v;
    }
}

sub get_hosts_with {
    my ($self, $local_context) = @_;
    my $hosts = $self->hosts;

    my $found = {};
    return [grep { not $found->{$_}++ } _get_hosts $hosts, $local_context];
}

sub get_desc_with {
    my ($self, $local_context) = @_;
    my $desc = $self->{args}->{desc};
    if (defined $desc and ref $desc eq 'CODE') {
        return $local_context->eval($desc);
    } else {
        $desc = $local_context->get_role_desc_by_name($self->name)
            unless defined $desc;
        return $desc; # or undef
    }
}

1;
