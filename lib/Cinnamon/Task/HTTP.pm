package Cinnamon::Task::HTTP;
use strict;
use warnings;
use Exporter::Lite;
use Web::UserAgent::Functions ();
use Web::UserAgent::Functions::Proxy qw(choose_socks_proxy_url);
use JSON::Functions::XS qw(perl2json_bytes);
use Cinnamon::DSL;
use Cinnamon::Config::User;

our @EXPORT = qw(http_get http_post http_post_data http_post_json);

Web::UserAgent::Functions->check_socksify;

our $DEBUG = $ENV{CINNAMON_HTTP_DEBUG};

sub _with_proxy ($$) {
    my ($url, $code) = @_;
    
    my $conf = get_user_config 'http.socks';
    if (defined $conf and not ref $conf eq 'ARRAY') {
        log error => 'Config |http.socks| is not an array';
        $conf = [];
    }
    local $Web::UserAgent::Functions::Proxy::DEBUG = $DEBUG;
    my $socks_url = choose_socks_proxy_url $conf, $url;
    if ($socks_url) {
        local $Web::UserAgent::Functions::SocksProxyURL = $socks_url;
        return $code->();
    } else {
        return $code->();
    }
}

sub _http ($%) {
    my $method = shift;
    my %args = @_;
    if (in_task_process) {
        my $cb = delete $args{cb};
        my $result = invoke_in_main_process {
            name => __PACKAGE__ . '::_http',
            args => [$method, %args, anyevent => 1],
            context => 'list',
            async => 'cb',
        };
        $cb->(@{$result->{return}}) if $cb;
        return $result->{return};
    } else {
        die "sync mode is not supported" unless $args{anyevent};
        return _with_proxy $args{url}, sub {
            return Web::UserAgent::Functions->can($method)->(%args);
        };
    }
}

sub http_get (%) {
    return _http('http_get', @_);
}

sub http_post (%) {
    return _http('http_post', @_);
}

sub http_post_data (%) {
    return _http('http_post_data', @_);
}

sub http_post_json (%) {
    my %args = @_;
    $args{header_fields}->{'Content-Type'} = 'application/json';
    $args{content} = perl2json_bytes $args{content};
    return _http('http_post_data', %args);
}

1;
