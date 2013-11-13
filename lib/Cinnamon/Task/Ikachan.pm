package Cinnamon::Task::Ikachan;
use strict;
use warnings;
use AnyEvent;
use Cinnamon::Task::HTTP;
use Cinnamon::DSL;
use Exporter::Lite;

our @EXPORT = qw(ikachan_notice);

sub ikachan_notice ($) {
    my ($msg) = @_;
    my $host = get 'ikachan_host';
    my $channel = get 'ikachan_channel';

    my $cv = AnyEvent->condvar;
    http_post
        anyevent => 1,
        url => qq<http://$host/notice>,
        params => {
            channel => $channel,
            message => $msg,
        },
        cb=>sub {
            $cv->send;
        };
    $cv->recv;
}

task ikachan => {
    notice => sub {
        my ($host, $message) = @_;
        my $user = get_operator_name;
        ikachan_notice sprintf '%s[%s]: %s @%s %s %s',
            (get 'ikachan_app_name'),
            (defined $host ? $host : undef),
            $user,
            (get 'role'),
            (get 'task'),
            defined $message ? $message . ' ' : '';
    },
};

1;
