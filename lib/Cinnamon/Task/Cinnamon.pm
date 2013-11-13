package Cinnamon::Task::Cinnamon;
use strict;
use warnings;
use Cinnamon::DSL;

task ['cinnamon', 'role', 'list'] => sub {
    my $state = shift;
    my $role_defs = $state->context->roles;
    log info => "Available roles:\n" .
        join "", map {
            my $desc = $state->context->get_role($_)->get_desc_with($state->context->get_param('get_role_desc_for'), $Cinnamon::LocalContext);
            "- " . $_ . (defined $desc ? "\t- $desc" : '') . "\n";
        } sort { $a cmp $b } keys %$role_defs;
    return $state->create_result;
}, {hosts => 'none'};

task ['cinnamon', 'role', 'hosts'] => my $host_list = sub {
    my $state = shift;
    my $file_name = $state->args->[0];
    if (defined $file_name) {
        open my $file, '>', $file_name or die "$0: $file_name: $!";
        print $file join ',', @{$state->hosts};
    } else {
        log info => join ',', @{$state->hosts};
    }
    return $state->create_result;
}, {hosts => 'all'};

task ['cinnamon', 'task', 'list'] => my $task_list = sub {
    my $state = shift;
    my $prefix = $state->args->[0];
    $prefix = '' unless defined $prefix;
    $prefix .= ':' if length $prefix and not $prefix =~ /:\z/;
    my $task_defs = $state->context->get_task($prefix);
    $task_defs = $task_defs ? $task_defs->tasks : {};
    log info => "Available tasks:\n" .
        join "", map {
            my $def = $task_defs->{$_};
            my $desc = $def->get_desc_with($Cinnamon::LocalContext);
            $desc = '' unless defined $desc;
            "- $prefix" . $_ . ($def->has_subtasks ? ':' : '') . "\t".(length $desc ? '-' : '')." $desc\n";
        } sort { $a cmp $b } keys %$task_defs;
    return $state->create_result;
}, {hosts => 'none'};

task ['cinnamon', 'task', 'default'] => sub {
    my $state = shift;
    $task_list->($state);
    log info => 'Hosts:';
    $host_list->($state);
    return $state->create_result;
}, {hosts => 'all'};

1;
