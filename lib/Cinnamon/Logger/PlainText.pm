package Cinnamon::Logger::PlainText;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub print {
    my ($self, $type, $message) = @_;

    if ($self->{last_type} and $self->{last_type} ne $type) {
        if (not $self->{has_newline}) {
            $message = "\n" . $message;
        }
    }
    $self->{last_type} = $type;
    $self->{has_newline} = $message =~ /\n$/;

    CORE::print { $self->{stdout} } $message;
}

1;
