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

sub print {
    my ($self, $type, $message) = @_;
    my $color ||= $COLOR{$type};

    $message = Term::ANSIColor::colored $message, $color if $color;

    if ($self->{last_type} and $self->{last_type} ne $type) {
        if (not $self->{has_newline}) {
            $message = "\n" . $message;
        }
    }
    $self->{last_type} = $type;
    $self->{has_newline} = $message =~ /\n$/;

    my $fh = $type eq 'error' ? $self->{stderr} : $self->{stdout};
    CORE::print $fh $message;
}

1;
