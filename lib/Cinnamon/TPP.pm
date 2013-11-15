package Cinnamon::TPP;
use strict;
use warnings;
use Storable ();
use Exporter::Lite;

# Task-process protocol
our @EXPORT = qw(tpp_parse tpp_serialize);

sub tpp_parse ($) {
    my $line = $_[0];
    $line =~ tr/\x0D\x0A//d;
    $line =~ s/\\([0-9A-F]{2})/pack 'C', hex $1/ge;
    return Storable::thaw ($line);
}

sub tpp_serialize ($) {
    my $data = Storable::freeze($_[0]);
    $data =~ s/([\x0D\x0A\x5C])/sprintf '\\%02X', ord $1/ge;
    return $data . "\x0A";
}

1;
