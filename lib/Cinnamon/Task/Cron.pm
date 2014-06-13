package Cinnamon::Task::Cron;
use strict;
use warnings;
use Cinnamon::DSL;

task cron => undef, {desc => 'cron'};

task ['cron', 'list'] => sub {
    my ($host, @args) = @_;
    remote {
        sudo q<sh -c 'echo; for file in $(ls /etc/cron.d/); do echo "# $file"; cat "/etc/cron.d/$file"; echo; done'>;
    } $host, user => get 'cron_user';
}, {desc => 'Show currently installed cron schedules'};

task ['cron', 'install'] => sub {
    my ($host, @args) = @_;
    remote {
        my $dir = get 'deploy_dir';
        sudo "cp -v $dir/local/config/cron.d/* /etc/cron.d/";
        sudo 'chown -R root:root /etc/cron.d/';
        sudo 'chmod -R 0644 /etc/cron.d/';
        sudo 'chmod 0700 /etc/cron.d/';
    } $host, user => get 'cron_user';
}, {desc => 'Install cron schedules'};

task ['cron', 'reload'] => sub {
    my ($host, @args) = @_;
    my $crond = get('cron_init') || '/etc/init.d/crond';
    remote {
        sudo "$crond reload";
    } $host, user => get 'cron_user';
}, {desc => 'Let cron reload configurations'};

task ['cron', 'log'] => undef, {desc => 'Logs'};

task ['cron', 'log', 'tail'] => sub {
    my ($host, @args) = @_;
    remote {
        sudo_stream 'tail -f /var/log/cron';
    } $host, user => get 'cron_user';
}, {desc => 'Tail cron log'};

task ['cron', 'config'] => undef, {desc => 'Cron configurations'};

task ['cron', 'config', 'create_file'] => sub {
    my $state = shift;
    my $name = $state->args->[0];
    $name = 'example' unless defined $name and length $name;
    run 'mkdir', '-p', 'config/cron.d.in';
    run 'touch', 'config/cron.d.in/' . $name . '-cron';
    log info => q{Add following lines to your Makefile:
batch-server:
	mkdir -p local/config/cron.d
	cd config/cron.d.in && ls *-cron | \
            xargs -l1 -i% -- sh -c "cat % | sed 's/@@ROOT@@/$(subst /,\/,$(abspath .))/g' > ../../local/config/cron.d/%"
};
    return $state->create_result;
}, {desc => '(local) Create schedule file placeholder', hosts => 'none'};

!!1;
