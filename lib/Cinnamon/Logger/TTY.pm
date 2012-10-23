package Cinnamon::Logger::TTY;
use strict;
use warnings;
use Term::ANSIColor ();

my %COLOR = (
    success => 'green',
    error   => 'red',
    info    => '',
);

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub log {
    my ($self, $type, $message) = @_;
    my $color ||= $COLOR{$type};

    $message = Term::ANSIColor::colored $message, $color if $color;
    $message .= "\n";

    my $fh = $type eq 'error' ? $self->{stderr} : $self->{stdout};
    print $fh $message;
}

1;
