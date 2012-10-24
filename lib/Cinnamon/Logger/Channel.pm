package Cinnamon::Logger::Channel;
use strict;
use warnings;
use Cinnamon::Logger;

sub new {
    my $class = shift;
    return bless {line_number => 1, has_newline => 1, @_}, $class;
}

sub print {
    my ($self, $s) = @_;

    my $type = $self->{type} || '';

    my $prefix = '';
    my $label = $self->{label};
    if (defined $label) {
        $prefix .= '[' . $label . '] ';
    }

    while ($s =~ s{([^\x0D\x0A]*)\x0D?\x0A}{}) {
        if ($self->{has_newline}) {
            Cinnamon::Logger->print(
                $type,
                $prefix . $self->{line_number} . ': ' . $1 . "\n",
            );
            $self->{line_number}++;
        } else {
            Cinnamon::Logger->print(
                $type,
                $1 . "\n",
            );
        }
        $self->{has_newline} = 1;
    }

    if (length $s) {
        if ($self->{has_newline}) {
            Cinnamon::Logger->print(
                $type,
                $prefix . $self->{line_number} . ': ' . $s,
            );
            $self->{line_number}++;
        } else {
            Cinnamon::Logger->print(
                $type,
                $s,
            );
        }
        $self->{has_newline} = 0;
    }
}

1;
