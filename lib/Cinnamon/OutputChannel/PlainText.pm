package Cinnamon::OutputChannel::PlainText;
use strict;
use warnings;
use Cinnamon::OutputChannel;
push our @ISA, qw(Cinnamon::OutputChannel);
use Encode;

sub new_from_fh {
    return bless {fh => $_[1]}, $_[0];
}

sub print {
    my ($self, $message, %args) = @_;
    $args{class} = '' unless defined $args{class};

    $message .= "\n" if $args{newline};

    if (defined $self->{last_class} and $self->{last_class} ne $args{class}) {
        $message = "\n" . $message unless $self->{has_newline};
    }
    $self->{last_class} = $args{class};
    $self->{has_newline} = $message =~ /\n$/;

    CORE::print { $self->{fh} } encode 'utf-8', $message;
}

1;
