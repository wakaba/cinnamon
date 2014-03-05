package Cinnamon::Task::Daemontools;
use strict;
use warnings;
use Cinnamon::DSL;
use Cinnamon::Task::Process;
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
                sudo 'svc', '-u', $dir . '/' . $service->($name);
                $onnotice->('svc -u');

                my $status1 = get_svstat $dir . '/' . $service->($name);
                my $stable;
                my $i = 0;
                {
                    sleep 1;
                    my $status2 = get_svstat $dir . '/' . $service->($name);
                    if ($status2->{status} eq 'up' and
                        $status1->{status} eq 'up' and
                        $status1->{pid} == $status2->{pid}) {
                        $stable = 1;
                        last;
                    }

                    last if $i++ > 5;
                    sudo 'svc', '-u', $dir . '/' . $service->($name);
                    $onnotice->("svc -u ($i)");
                    $status1 = $status2;
                    redo;
                }
                die "svc -u likely failed\n"
                    unless $status1->{status} eq 'up' and $stable;
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
                        $mode = $i > 5 ? $i > 8 ? 'k' : 't' : 'd';
                    } elsif ($i > 7) {
                        $mode = 'k';
                    }
                    if ($mode) {
                        if ($mode eq 'd') {
                            sudo 'svc', '-d', $dir . '/' . $service->($name);
                            $onnotice->("svc -d ($i)");
                        } elsif ($mode eq 't') {
                            kill_process_descendant 15, $status->{pid};
                            $onnotice->("SIGTERM ($i)");
                        } elsif ($mode eq 'k') {
                            kill_process_descendant 9, $status->{pid};
                            $onnotice->("SIGKILL ($i)");
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
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                my $service_dir = $dir . '/' . $service->($name);

                my $status0 = get_svstat $service_dir;
                if ($status0->{status} eq 'down' or
                    $status0->{status} eq 'unknown') {
                    call "$task_ns:start", $host, @args;
                } else {
                    $status0->{pid} ||= 0;

                    sudo 'svc', '-t', $service_dir;
                    $onnotice->('svc -t');

                    my $restarted;
                    my $stable;
                    my $i = 0;
                    my $status1;
                    {
                        $status1 = get_svstat $service_dir;
                        if ($status1->{status} eq 'up' and
                            $status1->{pid} != $status0->{pid}) {
                            $restarted = 1;
                        }
                        sleep 1;
                    }
                    {
                        my $status2 = get_svstat $service_dir;
                        if ($status2->{status} eq 'up' and
                            $status2->{pid} != $status0->{pid}) {
                            $restarted = 1;
                        }
                        if ($restarted and
                            $status1->{pid} == $status2->{pid}) {
                            $stable = 1;
                            last;
                        }
                        $status1 = $status2;
                        $i++;
                        if ($status2->{status} eq 'up' and
                            $status0->{pid} == $status2->{pid}) {
                            if ($i > 8) {
                                kill_process_descendant 9, $status2->{pid};
                                $onnotice->("SIGKILL ($i)");
                            } elsif ($i > 5) {
                                kill_process_descendant 15, $status2->{pid};
                                $onnotice->("SIGTERM ($i)");
                            } elsif ($i > 2) {
                                sudo 'svc', '-t', $service_dir;
                                $onnotice->("svc -t ($i)");
                            }
                            last if $i > 20;
                        } else {
                            last if $i > 10;
                        }
                        sleep 1;
                        redo;
                    }

                    die "svc -t failed\n" unless $restarted and $stable;
                }
            } $host, user => $user;
        },
        status => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_user';
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'svstat', $dir . '/' . $service->($name);
            } $host, user => $user;
        },
        process => {
            list => sub {
                my ($host, @args) = @_;
                my $user = get 'daemontools_user';
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    my $status = get_svstat $dir . '/' . $service->($name);
                    if ($status->{status} eq 'up') {
                        my $processes = ps;
                        my $get_tree; $get_tree = sub {
                            my ($pid, $indent) = @_;
                            my $result = '';
                            my $this = $processes->{$pid};
                            if ($this) {
                                $result .= $indent . "$pid $this->{command}\n";
                            }
                            for (keys %$processes) {
                                next unless $processes->{$_}->{ppid} == $pid;
                                $result .= $get_tree->($_, $indent . '  ');
                            }
                            return $result;
                        };
                        my $parent = $processes->{$processes->{$status->{pid}}->{ppid}};
                        log info => "$parent->{pid} $parent->{command}\n" . $get_tree->($status->{pid}, '  ');
                    }
                } $host, user => $user;
            },
        },
        log => {
            restart => sub {
                my ($host, @args) = @_;
                my $user = get 'daemontools_user';
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc', '-t', $dir . '/' . $service->($name) . '/log';
                } $host, user => $user;
            },
            start => sub {
                my ($host, @args) = @_;
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc', '-u', $dir . '/' . $service->($name) . '/log';
                } $host;
            },
            stop => sub {
                my ($host, @args) = @_;
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svc', '-d', $dir . '/' . $service->($name) . '/log';
                } $host;
            },
            status => sub {
                my ($host, @args) = @_;
                my $user = get 'daemontools_user';
                remote {
                    my $dir = get 'daemontools_service_dir';
                    my $service = get 'get_daemontools_service_name';
                    sudo 'svstat', $dir . '/' . $service->($name) . '/log';
                } $host, user => $user;
            },
            tail => (taskdef {
                my $state = shift;
                my $cv = $state->create_result_cv;
                my $user = get 'daemontools_user';
                my $file_names = [(get 'get_daemontools_log_file_name')->($name)];
                for my $host (@{$state->hosts}) {
                    $cv->begin_host($host);
                    $state->remote(host => $host, user => $user)->run_as_cv(['tail', '--follow=name', @$file_names])->cb(sub {
                        $cv->end_host($host, $_[0]->recv);
                    });
                }
                return $cv->return;
            } {desc => 'Tail log files', hosts => 'all'}),
        },
        uninstall => sub {
            my ($host, @args) = @_;
            my $user = get 'daemontools_setup_user';
            $user = get 'daemontools_user' if not defined $user;
            undef $user if defined $user and not length $user;
            remote {
                my $dir = get 'daemontools_service_dir';
                my $service = get 'get_daemontools_service_name';
                sudo 'mv', $dir . '/' . $service->($name), $dir . '/.' . $service->($name);
                sudo 'svc', '-dx', $dir . '/.' . $service->($name);
                sudo 'svc', '-dx', $dir . '/.' . $service->($name) . '/log';
                sudo 'rm', '-fr', $dir . '/.' . $service->($name);
                $onnotice->('svc -x');
            } $host, user => $user;
        },
    );
}

task daemontools => {
    yum_install => sub {
        my ($host, @args) = @_;
        my $package = (get 'daemontools_rpm_package') || 'daemontools-toaster';
        remote {
            sudo 'yum', 'install', '-y', $package;
            sudo '/sbin/chkconfig', 'svscan', 'on';
        } $host, user => get 'daemontools_setup_user';
    },
    svscan => {
        start => sub {
            my ($host, @args) = @_;
            remote {
                sudo '/etc/init.d/svscan', 'start';
            } $host, user => get 'daemontools_setup_user';
        },
        stop => sub {
            my ($host, @args) = @_;
            remote {
                sudo '/etc/init.d/svscan', 'stop';
            } $host, user => get 'daemontools_setup_user';
        },
        restart => sub {
            my ($host, @args) = @_;
            call 'daemontools:svscan:stop', $host, @args;
            call 'daemontools:svscan:start', $host, @args;
        },
    },
    service_template => {
        create => sub {
            my ($host, $template_name, $service_type, @args) = @_;
            die "Template name is not specified" unless defined $template_name;
            $service_type = $template_name unless defined $service_type;

            run 'mkdir', '-p', "config/service.in/$service_type/log";
            my $repo = qq<https://raw.github.com/wakaba/perl-setupenv/master/templates/daemontools/$template_name>;
            my $dir = qq<config/service.in/$service_type>;

            my $command = q{curl %s | sed 's/@@SERVICETYPE@@/%s/g' > %s};
            $service_type =~ s{/}{\\/}g;
            run sprintf $command, "$repo/run", $service_type, "$dir/run";
            run sprintf $command, "$repo/bin.sh", $service_type, "$dir/bin.sh";
            run sprintf $command, "$repo/log-run", $service_type, "$dir/log/run";
        },
    },
};

1;
