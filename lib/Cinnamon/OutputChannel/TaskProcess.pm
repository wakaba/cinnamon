package Cinnamon::OutputChannel::TaskProcess;
use strict;
use warnings;
use Cinnamon::OutputChannel;
push our @ISA, qw(Cinnamon::OutputChannel);

sub new_from_local_context {
    return bless {local_context => $_[1]}, $_[0];
}

sub print {
    my $self = shift;
    my $msg = shift;
    $self->{local_context}->tpp_parent_operation({
        type => 'logger',
        message => $msg,
        args => {@_},
    });
}

1;
