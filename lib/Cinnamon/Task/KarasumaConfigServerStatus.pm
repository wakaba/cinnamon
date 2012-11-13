package Cinnamon::Task::KarasumaConfigServerStatus;
use strict;
use warnings;
use Cinnamon::DSL;
use Cinnamon::Logger;
use Cinnamon::Task::HTTP;
use Exporter::Lite;
use AnyEvent;

our @EXPORT = qw(define_kcss_tasks);

sub define_kcss_tasks ($;%) {
    my ($name, %args) = @_;

    my $onnotice = $args{onnotice} || sub { };

    return (
        up => sub {
            my ($host, @args) = @_;
            remote {
                my $port = (get 'get_kcss_port')->($name);
                my $auth = (get 'get_kcss_basic_auth')->($name);
                my $cv = AE::cv;
                my ($req, $res);
                http_post
                    url => qq<http://$host:$port/admin/server/avail>,
                    params => {action => 'up'},
                    basic_auth => $auth,
                    anyevent => 1,
                    cb => sub {
                        ($req, $res) = @_;
                        $cv->send;
                    };
                $cv->recv;
                die $res->status_line . "\n" if $res->is_error;
                {
                    my $cv = AE::cv;
                    my ($req, $res);
                    http_post
                        url => qq<http://$host:$port/server/avail>,
                        anyevent => 1,
                        cb => sub {
                            ($req, $res) = @_;
                            $cv->send;
                        };
                    $cv->recv;
                    die "up failed\n" unless $res->code == 200;
                }
                $onnotice->();
            } $host;
        },
        down => sub {
            my ($host, @args) = @_;
            remote {
                my $port = (get 'get_kcss_port')->($name);
                my $auth = (get 'get_kcss_basic_auth')->($name);
                my $cv = AE::cv;
                my ($req, $res);
                http_post
                    url => qq<http://$host:$port/admin/server/avail>,
                    params => {action => 'down'},
                    basic_auth => $auth,
                    anyevent => 1,
                    cb => sub {
                        ($req, $res) = @_;
                        $cv->send;
                    };
                $cv->recv;
                warn $res->status_line if $res->is_error;
                {
                    my $cv = AE::cv;
                    my ($req, $res);
                    http_post
                        url => qq<http://$host:$port/server/avail>,
                        anyevent => 1,
                        cb => sub {
                            ($req, $res) = @_;
                            $cv->send;
                        };
                    $cv->recv;
                    warn "down failed\n" unless $res->code >= 500;
                }
                $onnotice->();
            } $host;
        },
        avail => sub {
            my ($host, @args) = @_;
            {
                my $port = (get 'get_kcss_port')->($name);
                my $auth = (get 'get_kcss_basic_auth')->($name);
                my $cv = AE::cv;
                my ($req, $res);
                http_post
                    url => qq<http://$host:$port/server/avail>,
                    anyevent => 1,
                    cb => sub {
                        ($req, $res) = @_;
                        $cv->send;
                    };
                $cv->recv;
                if ($res->code == 200) {
                    log success => $host . ': ' . $res->code . ' (' . $res->content . ")\n";
                } else {
                    log error => $host . ': ' . $res->code . ' (' . $res->content . ")\n";
                }
            };
        },
    );
}

1;
