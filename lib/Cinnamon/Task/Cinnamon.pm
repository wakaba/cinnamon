package Cinnamon::Task::Cinnamon;
use strict;
use warnings;
use Cinnamon::DSL;
use Cinnamon::Config;
use Cinnamon::Logger;

task 'cinnamon' => {
    role => {
        list => sub {
            my ($task, @args) = @_;
            my $role_defs = Cinnamon::Config::get_role_list;
            log info => "Available roles:\n" .
                join "", map {
                    my $desc = Cinnamon::Config::get_role_desc($_);
                    "- " . $_ . (defined $desc ? "\t- $desc" : '') . "\n";
                } sort { $a cmp $b } keys %$role_defs;
        },
        hosts => sub {
            my ($task, $hosts, $file_name) = @_;
            my $file = \*STDOUT;
            if (defined $file_name) {
                undef $file;
                open $file, '>', $file_name or die "$0: $task: $file_name: $!";
            }
            print $file join ',', @$hosts;
        },
    },
    task => {
        list => sub {
            my ($task, $prefix, @args) = @_;
            $prefix = '' unless defined $prefix;
            $prefix .= ':' if length $prefix and not $prefix =~ /:\z/;
            my $task_defs = Cinnamon::Config::get_task_list $prefix;
            $task_defs = $task_defs ? $task_defs->tasks : {};
            log info => "Available tasks:\n" .
                join "", map {
                    my $def = $task_defs->{$_};
                    my $desc = $def->get_desc;
                    $desc = '' unless defined $desc;
                    "- $prefix" . $_ . ($def->has_subtasks ? ':' : '') . "\t".(length $desc ? '-' : '')." $desc\n";
                } sort { $a cmp $b } keys %$task_defs;
        },
    },
};

1;
