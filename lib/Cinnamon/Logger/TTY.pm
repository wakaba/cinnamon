package Cinnamon::Logger::TTY;
use strict;
use warnings;
use Encode;
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
    my ($self, $type, $message, %args) = @_;
    my $color = !!$Cinnamon::Logger::OUTPUT_COLOR ? $COLOR{$type} : 0;

    $message = Term::ANSIColor::colored $message, $color if $color;
    $message .= "\n" if $args{newline};

    if ($self->{last_type} and $self->{last_type} ne $type) {
        if (not $self->{has_newline}) {
            $message = "\n" . $message;
        }
    }
    $self->{last_type} = $type;
    $self->{has_newline} = $message =~ /\n$/;

    my $fh = $type eq 'error' ? $self->{stderr} : $self->{stdout};
    CORE::print $fh encode 'utf-8', $message;
}

1;
