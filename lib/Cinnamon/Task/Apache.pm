package Cinnamon::Task::Apache;
use strict;
use warnings;
use Cinnamon::DSL;

task apache => {
    configtest => sub {
        my ($host, @args) = @_;
        my $crond = get('apache_init') || get('httpd_script') || '/etc/init.d/httpd';
        remote {
            sudo $crond, 'configtest';
        } $host, user => get 'apache_user';
    },
    reload => sub {
        my ($host, @args) = @_;
        my $crond = get('apache_init') || get('httpd_script') || '/etc/init.d/httpd';
        remote {
            sudo $crond, 'reload';
        } $host, user => get 'apache_user';
    },
    restart => sub {
        my ($host, @args) = @_;
        my $crond = get('apache_init') || get('httpd_script') || '/etc/init.d/httpd';
        remote {
            sudo $crond, 'restart';
        } $host, user => get 'apache_user';
    },
};

!!1;
