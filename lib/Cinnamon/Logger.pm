package Cinnamon::Logger;
use strict;
use warnings;
use Exporter::Lite;
use IO::Handle;

our @EXPORT = qw(
    log
);

our $Logger;
our $LoggerClass = 'Cinnamon::Logger::PlainText';

sub init_logger {
    if (-t STDOUT) {
        $LoggerClass = 'Cinnamon::Logger::TTY';
    }
    eval qq{ require $LoggerClass } or die $@;
    $Logger = $LoggerClass->new(
        stdout => \*STDOUT,
        stderr => \*STDERR,
    );
}

sub log ($$) {
    my ($type, $message) = @_;
    $Logger->log($type, $message);
    return;
}

STDOUT->autoflush(1);
STDERR->autoflush(1);

!!1;
