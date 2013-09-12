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
    my ($class, %args) = @_;
    if (-t STDOUT) {
        $LoggerClass = 'Cinnamon::Logger::TTY';
    }
    eval qq{ require $LoggerClass } or die $@;
    $Logger = $LoggerClass->new(
        stdout => \*STDOUT,
        stderr => \*STDERR,
        no_color => $args{no_color},
    );
}

sub log ($$) {
    my ($type, $message) = @_;
    $Logger->print($type, $message, newline => 1);
    return;
}

sub print {
    my (undef, $type, $message) = @_;
    $Logger->print($type, $message);
    return;
}

STDOUT->autoflush(1);
STDERR->autoflush(1);

!!1;
