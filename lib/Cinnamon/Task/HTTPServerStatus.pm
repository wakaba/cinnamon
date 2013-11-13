package Cinnamon::Task::HTTPServerStatus;
use strict;
use warnings;
use Cinnamon::DSL;
use Cinnamon::Task::HTTP;

task httpserverstatus => {
    show => sub {
        my ($host, @args) = @_;
        my $port = (get 'httpserverstatus_port') || 80;
        my $path = (get 'httpserverstatus_path') || '/server/status';
        my $auth = get 'httpserverstatus_basic_auth';
        my $cv = AE::cv;
        http_get
            url => qq<http://$host:$port$path>,
            basic_auth => $auth,
            anyevent => 1,
            cb => sub {
                my (undef, $res) = @_;
                die "Can't get server status\n" if $res->is_error;
                log info => $res->content;
                $cv->send;
            };
        $cv->recv;
    },
};

1;
