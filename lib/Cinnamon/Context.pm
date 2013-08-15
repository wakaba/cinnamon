package Cinnamon::Context;
use strict;
use warnings;

use Class::Load ();

use Cinnamon::Config;
use Cinnamon::Logger;
use Cinnamon::Task::Cinnamon;

sub new {
    my $class = shift;
    bless { }, $class;
}

sub run {
    my ($self, $role, $task, %opts)  = @_;
    Cinnamon::Logger->init_logger;

    $role =~ s/^\@// if defined $role;
    Cinnamon::Config::set role => $role;
    Cinnamon::Config::set task => $task;

    # XXX This should not be executed more than once by ./cin @role task1 task2
    Cinnamon::Config::load $role, $task, %opts;

    if ($opts{info}) {
        require YAML;
        log 'info', YAML::Dump(Cinnamon::Config::info);
        return ([], []);
    }

    my $args = $opts{args};
    my $hosts = my $orig_hosts = Cinnamon::Config::get_role;
    $hosts = $opts{hosts} if $opts{hosts};
    my $task_def = Cinnamon::Config::get_task;
    my $runner   = Cinnamon::Config::get('runner_class') || 'Cinnamon::Runner::Sequential';

    if (defined $task_def and ref $task_def eq 'HASH') {
        unshift @$args, $task;
        $task = 'cinnamon:task:list';
        Cinnamon::Config::set task => $task;
        $task_def = Cinnamon::Config::get_task;
    }

    if ($task eq 'cinnamon:role:hosts') {
        unshift @$args, $hosts || [];
        $hosts = [''];
    }

    unless (defined $orig_hosts) {
        if ($task =~ /^cinnamon:/) {
            $hosts ||= [''];
        } else {
            log 'error', "Role |\@$role| is not defined";
            return ([], ['undefined role']);
        }
    }
    unless (defined $task_def) {
        log 'error', "Task |$task| is not defined";
        return ([], ['undefined task']);
    }

    if (@$hosts == 0) {
        log error => "No host found for role '\@$role'";
    } elsif (@$hosts > 1 or $hosts->[0] ne '') {
        {
            my %found;
            $hosts = [grep { not $found{$_}++ } @$hosts];
        }

        my $desc = Cinnamon::Config::get_role_desc $role;
        log info => sprintf 'Host%s %s (@%s%s)',
            @$hosts == 1 ? '' : 's', (join ', ', @$hosts), $role,
            defined $desc ? ' ' . $desc : '';
        my $task_desc = ref $task_def eq 'Cinnamon::TaskDef' ? $task_def->get_param('desc') : undef;
        log info => sprintf 'call %s%s',
            $task, defined $task_desc ? " ($task_desc)" : '';
    }

    Class::Load::load_class $runner;

    my $result = Cinnamon::Config::with_local_config {
        $runner->start($hosts, $task_def, @$args);
    };
    my (@success, @error);
    
    for my $key (keys %{$result || {}}) {
        if ($result->{$key}->{error}) {
            push @error, $key;
        }
        else {
            push @success, $key;
        }
    }

    log success => sprintf(
        "\n========================\n[success]: %s",
        (join(', ', @success) || ''),
    );

    log error => sprintf(
        "[error]: %s",
        (join(', ', @error)   || ''),
    );

    return (\@success, \@error);
}

!!1;
