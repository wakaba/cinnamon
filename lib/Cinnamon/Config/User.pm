package Cinnamon::Config::User;
use strict;
use warnings;
use JSON::Functions::XS qw(file2perl);
use Path::Class;
use Exporter::Lite;

our @EXPORT;

my $UserConfig = {};
my $ConfigLoaded;

sub load_configs () {
    my $user_config_f = dir($ENV{HOME} || '.')->subdir('.cinnamon')->file('config.json');
    if (-f $user_config_f) {
        $UserConfig = file2perl $user_config_f;
    }
    $ConfigLoaded = 1;
}

push @EXPORT, qw(get_user_config);
sub get_user_config ($) {
    my ($key) = @_;
    load_configs unless $ConfigLoaded;
    return $UserConfig->{$key};
}

1;

=head1 EXAMPLE OF CONFIG.JSON

~/.cinnamon/config.json:

  {
    "http.socks": [
      {
        "target_hostname": "*.h",
        "hostname": "localhost",
        "port": 1080
      }
    ]
  }

=cut
