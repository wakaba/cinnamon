package Cinnamon::OutputChannel::TTY;
use strict;
use warnings;
use Cinnamon::OutputChannel;
push our @ISA, qw(Cinnamon::OutputChannel);
use Encode;
use Term::ANSIColor ();

my %COLOR = (
    success => 'green',
    error   => 'red',
    info    => '',
);

sub new_from_fh {
    return bless {fh => $_[1]}, $_[0];
}

sub no_color {
    if (@_ > 1) {
        $_[0]->{no_color} = $_[1];
    }
    return $_[0]->{no_color};
}

sub print {
    my ($self, $message, %args) = @_;
    $args{class} = '' unless defined $args{class};
    my $color = $self->no_color ? 0 : $COLOR{$args{class}};

    $message = Term::ANSIColor::colored $message, $color if $color;
    $message .= "\n" if $args{newline};

    if (defined $self->{last_class} and $self->{last_class} ne $args{class}) {
        $message = "\n" . $message unless $self->{has_newline};
    }
    $self->{last_class} = $args{class};
    $self->{has_newline} = $message =~ /\n$/;

    CORE::print { $self->{fh} } encode 'utf-8', $message;
}

1;
