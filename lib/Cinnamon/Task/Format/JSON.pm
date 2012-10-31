package Cinnamon::Task::Format::JSON;
use strict;
use warnings;
use Exporter::Lite;
use JSON::Functions::XS qw(json_bytes2perl json_chars2perl);

our @EXPORT;

push @EXPORT, qw(json_bytes2perl json_chars2perl);

1;
