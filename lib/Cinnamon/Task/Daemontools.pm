package Cinnamon::Task::Daemontools;
use strict;
use warnings;
use Cinnamon::DSL;
use Exporter::Lite;

our @EXPORT = qw(define_daemontools_tasks);

sub define_daemontools_tasks ($;%) {
    my ($name, %args) = @_;

    my $onnotice = $args{onnotice} || sub { };

    return (
        start => sub {
            my ($host, @args) = @_;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc -u ' . $dir . '/' . $service->($name);
                $onnotice->('svc -u');
            } $host;
        },
        stop => sub {
            my ($host, @args) = @_;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc -d ' . $dir . '/' . $service->($name);
                $onnotice->('svc -d');
            } $host;
        },
        restart => sub {
            my ($host, @args) = @_;
            remote {
                call "$name:stop", $host, @args;
                call "$name:start", $host, @args;
                #call "$name:log:tail", $host, @args;
            } $host;
        },
        status => sub {
            my ($host, @args) = @_;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svstat ' . $dir . '/' . $service->($name);
            } $host;
        },
        log => {
            restart => sub {
                my ($host, @args) = @_;
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc -t ' . $dir . '/' . $service->($name) . '/log';
                } $host;
            },
            status => sub {
                my ($host, @args) = @_;
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svstat ' . $dir . '/' . $service->($name) . '/log';
                } $host;
            },
            tail => sub {
                my ($host, @args) = @_;
                remote {
                    my $file_name = get 'get_daemontools_log_file_name';
                    run_stream "tail --follow=name " . $file_name->($name);
                } $host;
            },
        },
        uninstall => sub {
            my ($host, @args) = @_;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'mv ' . $dir . '/' . $service->($name) . ' ' . $dir . '/.' . $service->($name);
                sudo 'svc -dx ' . $dir . '/.' . $service->($name);
                sudo 'svc -dx ' . $dir . '/.' . $service->($name) . '/log';
                sudo 'rm ' . $dir . '/.' . $service->($name);
                $onnotice->('svc -x');
            } $host;
        },
    );
}

1;
