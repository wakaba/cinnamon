package Cinnamon::Config;
use strict;
use warnings;
use Carp;
use Cinnamon::Logger;

my %CONFIG;
my %ROLES;
my %TASKS;

sub set ($$) {
    my ($key, $value) = @_;

    $CONFIG{$key} = $value;
}

sub get ($@) {
    my ($key, @args) = @_;

    my $value = $CONFIG{$key};

    $value = $value->(@args) if ref $value eq 'CODE';
    $value;
}

sub set_role ($$$) {
    my ($role, $hosts, $params) = @_;

    $ROLES{$role} = [$hosts, $params];
}

sub _get_hosts {
    my $v = shift;
    if (not defined $v) {
        return ();
    } elsif (ref $v eq 'CODE') {
        return _get_hosts($v->());
    } elsif (ref $v eq 'ARRAY') {
        return map { _get_hosts($_) } @$v;
    } elsif (UNIVERSAL::can($v, 'to_a')) {
        return map { _get_hosts($_) } @{$v->to_a};
    } else {
        return $v;
    }
}

sub get_role (@) {
    my $role  = ($_[0] || get('role'));

    my $role_def = $ROLES{$role} or return undef;

    my ($hosts, $params) = @$role_def;

    for my $key (keys %$params) {
        set $key => $params->{$key};
    }

    my $found = {};
    return [grep { not $found->{$_}++ } _get_hosts $hosts];
}

sub set_role_alias ($$) {
    $ROLES{$_[0]} = $ROLES{$_[1]} || croak "Role |$_[1]| is not defined";
}

sub get_role_list (;$) {
    return \%ROLES;
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

    $role =~ s/^\@// if defined $role;

    set role => $role;
    set task => $task;
    set user => $opt{user};

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

!!1;
