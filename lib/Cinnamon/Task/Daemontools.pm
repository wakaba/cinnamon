package Cinnamon::Task::Daemontools;
use strict;
use warnings;
use Cinnamon::DSL;
use Exporter::Lite;

our @EXPORT = qw(define_daemontools_tasks);

sub get_svstat ($) {
    my $service = shift;
    my ($status) = sudo 'svstat', $service;

    # /service/hoge: down 1 seconds, normally up
    # /service/hoge: up (pid 1486) 0 seconds
    # /service/hoge: up (pid 11859) 6001 seconds, want down

    if ($status =~ /.+: (up) \(pid ([0-9]+)\) ([0-9]+) seconds(?:, (want (?:down|up)))?/) {
        return {status => $1, pid => $2, seconds => $3, additional => $4};
    } elsif ($status =~ /.+: (down) ([0-9]+) seconds/) {
        return {status => $1, seconds => $2};
    } else {
        return {status => 'unknown'};
    }
}

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

                my $status1 = get_svstat $dir . '/' . $service->($name);
                die "svc -u failed\n" unless $status1->{status} eq 'up';

                sleep 1;
                my $status2 = get_svstat $dir . '/' . $service->($name);
                die "svc -u failed\n" unless $status2->{status} eq 'up';
                die "svc -u likely failed\n"
                    if $status1->{pid} != $status2->{pid};
            } $host, user => $user;
        },
        stop => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_user';
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svc', '-d', $dir . '/' . $service->($name);
                $onnotice->('svc -d');

                my $timeout = 20;
                my $i = 0;
                my $mode;
                {
                    my $status = get_svstat $dir . '/' . $service->($name);
                    last if $status->{status} eq 'down';
                    if ($i > 2 and
                        (not $status->{additional} or
                         $status->{additional} ne 'want down')) {
                        $mode = $i > 5 ? 'k' : 'd';
                    } elsif ($i > 7) {
                        $mode = 'k';
                    }
                    if ($mode) {
                        if ($mode eq 'd') {
                            sudo 'svc', '-d', $dir . '/' . $service->($name);
                            $onnotice->("svc -d ($i)");
                        } elsif ($mode eq 'k') {
                            sudo 'svc', '-k', $dir . '/' . $service->($name);
                            $onnotice->("svc -k ($i)");
                        }
                    }
                    if ($i < $timeout) {
                        sleep 1;
                        $i++;
                        redo;
                    } else {
                        die "svc -d failed\n";
                    }
                }
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
            start => sub {
                my ($host, @args) = @_;
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc -u ' . $dir . '/' . $service->($name) . '/log';
                } $host;
            },
            stop => sub {
                my ($host, @args) = @_;
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc -d ' . $dir . '/' . $service->($name) . '/log';
                } $host;
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
