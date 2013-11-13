package Cinnamon::Task::HTTP;
use strict;
use warnings;
use Exporter::Lite;
use Web::UserAgent::Functions ();
use JSON::Functions::XS qw(perl2json_bytes);
use Cinnamon::Config::User;

our @EXPORT = qw(http_get http_post http_post_data http_post_json);

Web::UserAgent::Functions->check_socksify;

our $DEBUG = $ENV{CINNAMON_HTTP_DEBUG};

sub _with_proxy ($$) {
    my ($url, $code) = @_;
    
    my $socks_url;
    my $conf = get_user_config 'http.socks';
    if (defined $conf and not ref $conf eq 'ARRAY') {
        log error => 'Config |http.socks| is not an array';
        $conf = [];
    }
    for (@{$conf or []}) {
        my $pattern = join '\.',
            map { $_ eq '*' ? '.+' : quotemeta }
            split /\./,
                defined $_->{target_hostname} ? $_->{target_hostname} : '*';
        if ($url =~ m{^https?://$pattern[:/]}i) {
            warn "<$url> matches /$_->{target_hostname}/ ($pattern)\n" if $DEBUG;
            $socks_url = 'socks5://' .
                (defined $_->{hostname} ? $_->{hostname} : 'localhost') . 
                ':' . ($_->{port} || 0);
            last;
        } else {
            warn "<$url> does not match /$pattern/ ($_->{target_hostname})\n" if $DEBUG;
        }
    }

    if ($socks_url) {
        local $Web::UserAgent::Functions::SocksProxyURL = $socks_url;
        return $code->();
    } else {
        return $code->();
    }
}

sub http_get (%) {
    my %args = @_;
    die "sync mode is not supported" unless $args{anyevent};
    
    return _with_proxy $args{url}, sub {
        return Web::UserAgent::Functions::http_get(%args);
    };
}

sub http_post (%) {
    my %args = @_;
    die "sync mode is not supported" unless $args{anyevent};
    
    return _with_proxy $args{url}, sub {
        return Web::UserAgent::Functions::http_post(%args);
    };
}

sub http_post_data (%) {
    my %args = @_;
    die "sync mode is not supported" unless $args{anyevent};
    
    return _with_proxy $args{url}, sub {
        return Web::UserAgent::Functions::http_post_data(%args);
    };
}

sub http_post_json (%) {
    my %args = @_;
    die "sync mode is not supported" unless $args{anyevent};
    $args{header_fields}->{'Content-Type'} = 'application/json';
    
    return _with_proxy $args{url}, sub {
        return Web::UserAgent::Functions::http_post_data(
            %args,
            content => perl2json_bytes $args{content},
        );
    };
}

1;
