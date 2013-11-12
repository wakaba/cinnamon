package Cinnamon::Logger;
use strict;
use warnings;
use Exporter::Lite;
use Cinnamon qw(CTX);

our @EXPORT = qw(
    log
);

sub log ($$) {
    my ($type, $message) = @_;
    CTX->output_channel->print($message, newline => 1, class => $type);
    return;
}

!!1;
