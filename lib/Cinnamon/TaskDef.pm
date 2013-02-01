package Cinnamon::TaskDef;
use strict;
use warnings;
use overload
    '&{}' => sub { $_[0]->[0] },
    fallback => 1;

sub new_from_code_and_args {
    return bless [$_[1], $_[2]], $_[0];
}

sub get_param {
    my $value = $_[0]->[1]->{$_[1]};
    return defined $value ? ref $value eq 'CODE' ? $value->() : $value : $_[2];
}

1;
