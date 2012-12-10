package Cinnamon::Task::Cron;
use strict;
use warnings;
use Cinnamon::DSL;

task cron => {
    list => sub {
        my ($host, @args) = @_;
        remote {
            sudo q<sh -c 'echo; for file in $(ls /etc/cron.d/); do echo "# $file"; cat "/etc/cron.d/$file"; echo; done'>;
        } $host, user => get 'cron_user';
    },
    install => sub {
        my ($host, @args) = @_;
        remote {
            my $dir = get 'deploy_dir';
            sudo "cp -v $dir/local/config/cron.d/* /etc/cron.d/";
            sudo 'chown -R root:root /etc/cron.d/';
            sudo 'chmod -R 0644 /etc/cron.d/';
            sudo 'chmod 0700 /etc/cron.d/';
        } $host, user => get 'cron_user';
    },
    reload => sub {
        my ($host, @args) = @_;
        my $crond = get('cron_init') || '/etc/init.d/crond';
        remote {
            sudo "$crond reload";
        } $host, user => get 'cron_user';
    },
    log => sub {
        my ($host, @args) = @_;
        remote {
            sudo_stream 'tail -f /var/log/cron';
        } $host, user => get 'cron_user';
    },
};

!!1;
