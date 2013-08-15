package Cinnamon::Config;
use strict;
use warnings;
use Cinnamon;
use Cinnamon::Logger;

our %CONFIG; # Must not be accessed from outside of this module!
my %TASKS;

sub reset () {
    %CONFIG = ();
    %TASKS  = ();
}

sub with_local_config (&) {
    local %CONFIG = %CONFIG;
    return $_[0]->();
}

sub set ($$) {
    my ($key, $value) = @_;

    $CONFIG{$key} = $value;
}

sub set_default ($$) {
    my ($key, $value) = @_;

    $CONFIG{$key} = $value if not defined $CONFIG{$key};
}

sub get ($@) {
    my ($key, @args) = @_;

    my $value = $CONFIG{$key};

    $value = $value->(@args) if ref $value eq 'CODE';
    $value;
}

sub set_role ($$$;%) {
    my ($role, $hosts, $params, %args) = @_;
    CTX->set_role($role, $hosts, $params, \%args);
}

sub get_role (@) {
    my $role  = ($_[0] || get('role'));
    return CTX->get_role_hosts($role);
}

sub set_role_alias ($$) {
    CTX->set_role_alias($_[0] => $_[1]);
}

sub get_role_list () {
    return CTX->roles;
}

sub get_role_desc ($) {
    return CTX->get_role_desc($_[0]);
}

sub set_task ($$) {
    my ($task, $task_def) = @_;
    $TASKS{$task} = $task_def;
}

sub get_task (@) {
    my ($task) = @_;

    $task ||= get('task');
    my @task_path = split(':', $task);

    my $value = \%TASKS;
    for (@task_path) {
        $value = $value->{$_};
    }

    $value;
}

sub get_task_list (;$) {
    my ($task) = @_;
    
    my @task_path = defined $task ? split(':', $task) : ();

    my $value = \%TASKS;
    for (@task_path) {
        $value = $value->{$_};
    }

    return $value;
}

sub user () {
    get('user') || real_user();
}

sub real_user () {
    my $user = qx{whoami};
    chomp $user;
    return $user;
}

sub load (@) {
    my ($role, $task, %opt) = @_;

    return do {
        package Cinnamon::Config::Script;
        do $opt{config};
    } || do {
        if ($@) {
            log error => $@;
            exit 1;
        }

        if ($!) {
            log error => $!;
            exit 1;
        }
    };

    for my $key (keys %{ $opt{override_settings} }) {
        set $key => $opt{override_settings}->{$key};
    }
}

sub info {
    my $self  = shift;
    +{
        tasks => \%TASKS,
    }
}

!!1;
