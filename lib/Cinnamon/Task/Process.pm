package Cinnamon::Task::Process;
use strict;
use warnings;
use Exporter::Lite;
use Cinnamon::DSL;

our @EXPORT;

push @EXPORT, qw(ps);
sub ps (;) {
    my ($ps) = run {hide_output => 1},
        'ps', '-eo', 'pid,ppid,command';
    my $processes = {};
    for (split /\n/, $ps) {
        if (/^\s*(\d+)\s+(\d+)\s+(.+)/) {
            $processes->{$1} = {pid => $1, ppid => $2, command => $3};
        }
    }
    return $processes;
}

push @EXPORT, qw(kill_process_descendant);
sub kill_process_descendant ($$;$) {
    my ($signal, $pid, $opt) = @_;
    my @pid = (ref $pid ? @$pid : $pid);
    my $processes = ps;
    my @search = (@pid);
    while (@search) {
        my $id = shift @search;
        for (values %$processes) {
            if ($_->{ppid} == $id) {
                unshift @pid, $_->{pid};
                push @search, $_->{pid};
            }
        }
    }
    my %found;
    @pid = grep { not $found{$_}++ } @pid;
    log info => "kill @{[scalar @pid]} processes...";
    if (@pid) {
        run {%{$opt || {}}, ignore_error => 1}, 'kill', "-$signal", @pid;
        sleep 1;
        my $processes = ps;
        $processes = {map { $_->{pid} => 1 } values %$processes};
        @pid = grep { $processes->{$_} } @pid;
        if ($opt->{ignore_error}) {
            log error => "Can't kill processes @pid";
        } else {
            die "Can't kill processes @pid";
        }
    }
}

task process => {
    list => sub {
        my ($host, $grep, @args) = @_;
        remote {
            my $processes = ps;
            if (defined $grep) {
                $processes = {
                    map { $_ => $processes->{$_} }
                    grep { $processes->{$_}->{command} =~ /\Q$grep\E/ }
                    keys %$processes
                };
            }
            my $order = {
                pid => 1,
                ppid => 2,
                command => 3,
            };
            log info => join "\n", map {
                my $n = $_;
                join "\t", map { $_ . '=' . $processes->{$n}->{$_} } sort { $order->{$a} <=> $order->{$b} } keys %{$processes->{$n}};
            } sort { $a cmp $b } keys %$processes;
        } $host;
    },
    kill_all_descendants => sub {
        my ($host, @args) = @_;
        my $signal;
        my $grep;
        if (@args) {
            if ($args[0] =~ /^-/) {
                ($signal, $grep) = @args;
                $signal =~ s/^-//;
            } else {
                $signal = 15;
                ($grep) = @args;
            }
        }
        die "Command pattern is not specified" if not defined $grep;
        remote {
            my $processes = ps;
            $processes = {
                map { $_ => $processes->{$_} }
                grep { $processes->{$_}->{command} =~ /\Q$grep\E/ }
                keys %$processes
            };
            my $order = {
                pid => 1,
                ppid => 2,
                command => 3,
            };
            my @n;
            log info => join "\n", map {
                my $n = $_;
                push @n, $_;
                join "\t", map { $_ . '=' . $processes->{$n}->{$_} } sort { $order->{$a} <=> $order->{$b} } keys %{$processes->{$n}};
            } sort { $a cmp $b } keys %$processes;
            kill_process_descendant $signal || 0, \@n, {ignore_error => 1};
        } $host, user => get 'process_kill_user';
    },
};

1;
