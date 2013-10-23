package Cinnamon::TaskResult;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub failed {
    return $_[0]->{failed};
}

sub succeeded_hosts {
    return $_[0]->{succeeded_hosts} || [];
}

sub failed_hosts {
    return $_[0]->{failed_hosts} || [];
}

sub as_cv {
    my $cv = Cinnamon::TaskResult::CondVar->new;
    $cv->{result} = $_[0];
    $cv->begin(sub { $_[0]->send($_[0]->result) }); # (1)
    return $cv;
}

sub return_values {
    return $_[0]->{return_values} || {};
}

sub set_return_value {
    $_[0]->{return_values}->{$_[1]} = $_[2];
}

package Cinnamon::TaskResult::CondVar;
use AnyEvent;
push our @ISA, qw(AnyEvent::CondVar);

sub begin_host {
    $_[0]->begin; # (2)
}

sub end_host {
    $_[0]->end; # (2)
    my $result = $_[2];
    if (UNIVERSAL::isa ($result, 'Cinnamon::CommandResult')) {
        $result = not $result->has_error;
    }
    if ($result) {
        push @{$_[0]->{result}->{succeeded_hosts} ||= []}, $_[1];
    } else {
        push @{$_[0]->{result}->{failed_hosts} ||= []}, $_[1];
        $_[0]->{result}->{failed} = 1;
    }
}

sub return {
    $_[0]->end; # (1)
    return $_[0];
}

sub result {
    return $_[0]->{result};
}

1;
