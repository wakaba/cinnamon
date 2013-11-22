package Cinnamon::CLI::UIManager;
use strict;
use warnings;
use AnyEvent;

sub new {
    return bless {actions => []}, $_[0];
}

sub push_action {
    my ($self, $code) = @_;
    push @{$self->{actions}}, $code;
    return if @{$self->{actions}} > 1;
    my $run_next; $run_next = sub {
        my $action = $self->{actions}->[0] or return;
        AE::postpone {
            $action->(sub {
                shift @{$self->{actions}};
                $run_next->();
            });
        };
    };
    $run_next->();
}

1;

