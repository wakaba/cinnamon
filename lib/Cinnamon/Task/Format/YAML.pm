package Cinnamon::Task::Format::YAML;
use strict;
use warnings;
use Exporter::Lite;
use YAML::XS;
use Encode;

our @EXPORT;

push @EXPORT, qw(yaml_chars2perl);
sub yaml_chars2perl ($) {
    return YAML::XS::Load $_[0];
}

push @EXPORT, qw(yaml_bytes2perl);
sub yaml_bytes2perl ($) {
    return YAML::XS::Load decode 'utf-8', $_[0];
}

1;
