package Cinnamon::Task::KarasumaConfigJSON;
use strict;
use warnings;
use Karasuma::Config::JSON;
use Cinnamon::DSL;
use Path::Class;
use Exporter::Lite;

our @EXPORT = qw(config_json);

my $Config;

sub config_json () {
    return $Config ||= do {
        my $json_name = get 'kcjson_file';
        my $dir_name = get 'kcjson_keys_dir';
        my $config = Karasuma::Config::JSON->new_from_json_f(file($json_name));
        $config->base_d(dir($dir_name)) if defined $dir_name;
        $config;
    };
}

1;
