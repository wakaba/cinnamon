package Cinnamon::Config;
use strict;
use warnings;
use Carp;
use Cinnamon::Logger;

our %CONFIG; # Must not be accessed from outside of this module!
my %ROLES;
my %TASKS;

sub reset () {
    %CONFIG = ();
    %ROLES  = ();
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

    $ROLES{$role} = [$hosts, $params, \%args];
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

sub get_role_desc ($) {
    my $desc = $ROLES{$_[0]}->[2]->{desc};
    if (defined $desc and ref $desc eq 'CODE') {
        return $desc->();
    }
    if (not defined $desc) {
        my $code = get 'get_role_desc_for';
        $desc = $code->($_[0]) if $code;
    }
    return $desc;
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
    my %roles = map {
        my ($hosts, $params) = @{$ROLES{$_}};
        $hosts = $hosts->() if ref $hosts eq 'CODE';
        $_ => { hosts => $hosts, params => $params };
    } keys %ROLES;

    +{
        roles => \%roles,
        tasks => \%TASKS,
    }
}

!!1;
