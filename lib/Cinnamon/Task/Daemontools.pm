package Cinnamon::Task::Daemontools;
use strict;
use warnings;
use Cinnamon::DSL;
use Exporter::Lite;

our @EXPORT = qw(define_daemontools_tasks);

sub define_daemontools_tasks ($) {
    my $name = shift;
    return (
        start => sub {
            my ($host, @args) = @_;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc -u ' . $dir . '/' . $service->($name);
            } $host;
        },
        stop => sub {
            my ($host, @args) = @_;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc -d ' . $dir . '/' . $service->($name);
            } $host;
        },
        restart => sub {
            my ($host, @args) = @_;
            remote {
                my $task = get 'task';
                $task =~ s/:restart$//;
                call "$task:stop", $host, @args;
                call "$task:start", $host, @args;
                call "$task:log:tail", $host, @args;
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
            tail => sub {
                my ($host, @args) = @_;
                remote {
                    my $file_name = get 'get_daemontools_log_file_name';
                    run_stream "tail --follow=name " . $file_name->($name);
                } $host;
            },
        },
    );
}

1;
