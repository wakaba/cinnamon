package Cinnamon::Task::Daemontools;
use strict;
use warnings;
use Cinnamon::DSL;
use Exporter::Lite;

our @EXPORT = qw(define_daemontools_tasks);

sub define_daemontools_tasks ($;%) {
    my ($name, %args) = @_;
    my $task_ns = $args{namespace} || $name;

    my $onnotice = $args{onnotice} || sub { };

    return (
        start => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_user';
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc -u ' . $dir . '/' . $service->($name);
                $onnotice->('svc -u');
            } $host, user => $user;
        },
        stop => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_user';
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc -d ' . $dir . '/' . $service->($name);
                $onnotice->('svc -d');
            } $host, user => $user;
        },
        restart => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_user';
            remote {
                call "$task_ns:stop", $host, @args;
                call "$task_ns:start", $host, @args;
                #call "$task_ns:log:tail", $host, @args;
            } $host, user => $user;
        },
        status => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_user';
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svstat ' . $dir . '/' . $service->($name);
            } $host, user => $user;
        },
        log => {
            restart => sub {
                my ($host, @args) = @_;
                my $user = get 'daemontools_user';
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc -t ' . $dir . '/' . $service->($name) . '/log';
                } $host, user => $user;
            },
            status => sub {
                my ($host, @args) = @_;
                my $user = get 'daemontools_user';
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svstat ' . $dir . '/' . $service->($name) . '/log';
                } $host, user => $user;
            },
            tail => sub {
                my ($host, @args) = @_;
                my $user = get 'daemontools_user';
                remote {
                    my $file_name = get 'get_daemontools_log_file_name';
                    run_stream "tail --follow=name " . $file_name->($name);
                } $host, user => $user;
            },
        },
        uninstall => sub {
            my ($host, @args) = @_;
            my $user = (get 'daemontools_uninstall_user') || get 'daemontools_user';
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'mv ' . $dir . '/' . $service->($name) . ' ' . $dir . '/.' . $service->($name);
                sudo 'svc -dx ' . $dir . '/.' . $service->($name);
                sudo 'svc -dx ' . $dir . '/.' . $service->($name) . '/log';
                sudo 'rm ' . $dir . '/.' . $service->($name);
                $onnotice->('svc -x');
            } $host, user => $user;
        },
    );
}

1;
