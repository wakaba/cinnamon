package Cinnamon::OutputChannel::LinedStream;
use strict;
use warnings;
use Cinnamon::OutputChannel;
push our @ISA, qw(Cinnamon::OutputChannel);

sub new_from_output_channel {
    return bless {
        line_number => 1,
        has_newline => 1,
        output_channel => $_[1],
    }, $_[0];
}

sub class {
    if (@_ > 1) {
        $_[0]->{class} = $_[1];
    }
    return $_[0]->{class};
}

sub label {
    if (@_ > 1) {
        $_[0]->{label} = $_[1];
    }
    return $_[0]->{label};
}

sub output_channel {
    return $_[0]->{output_channel};
}

sub print {
    my ($self, $s, %args) = @_;

    my $type = $self->class;

    my $prefix = '';
    my $label = $self->label;
    if (defined $label) {
        $prefix .= '[' . $label . '] ';
    }

    my $out = $self->output_channel;
    while ($s =~ s{([^\x0D\x0A]*)\x0D?\x0A}{}) {
        if ($self->{has_newline}) {
            $out->print(
                $prefix . $self->{line_number} . ': ' . $1 . "\n",
                class => $type,
            );
            $self->{line_number}++;
        } else {
            $out->print($1 . "\n", class => $type);
        }
        $self->{has_newline} = 1;
    }

    if (length $s) {
        if ($self->{has_newline}) {
            $out->print(
                $prefix . $self->{line_number} . ': ' . $s,
                class => $type,
            );
            $self->{line_number}++;
        } else {
            $out->print($s, class => $type);
        }
        $self->{has_newline} = 0;
    }
}

1;
