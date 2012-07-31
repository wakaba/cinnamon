package Cinnamon::Logger;
use strict;
use warnings;
use parent qw(Exporter);
use IO::Handle;
use Term::ANSIColor ();

use Cinnamon::Config;

our @EXPORT = qw(
    log
);

my %COLOR = (
    success => 'green',
    error   => 'red',
    info    => '',
);

sub log ($$) {
    my ($type, $message) = @_;
    my $color ||= $COLOR{$type};

    $message = Term::ANSIColor::colored $message, $color if $color;
    $message .= "\n";

    my $fh = $type eq 'error' ? *STDERR : *STDOUT;

    print $fh $message;

    return;
}

STDOUT->autoflush(1);
STDERR->autoflush(1);

!!1;
