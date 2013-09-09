package Cinnamon::Config;
use strict;
use warnings;
use Cinnamon;
use Cinnamon::Logger;

push our @CARP_NOT, qw(Cinnamon);

sub set ($$) {
    CTX->set_param(@_);
}

sub set_default ($$) {
    CTX->set_param(@_) unless defined CTX->get_param($_[0]);
}

sub get ($@) {
    return CTX->get_param(@_);
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

sub _expand_tasks ($$$;$);
sub _expand_tasks ($$$;$) {
    my ($path, $task_def => $defs, $root_args) = @_;
    if (ref $task_def eq 'HASH') {
        push @$defs, {path => $path, args => $root_args};
        for (keys %$task_def) {
            _expand_tasks [@$path, $_], $task_def->{$_} => $defs;
        }
    } elsif (UNIVERSAL::isa($task_def, 'Cinnamon::TaskDef')) {
        push @$defs, {path => $path, code => $task_def->[0], args => $task_def->[1]};
    } else {
        push @$defs, {path => $path, code => $task_def, args => $root_args};
    }
}

sub set_task ($$;$) {
    my ($name, $task_def, $root_args) = @_;
    my $defs = [];
    _expand_tasks [$name] => $task_def => $defs, $root_args;
    CTX->define_tasks($defs);
}

sub get_task (@) {
    my ($t) = @_;
    $t ||= get('task');
    my $path = [split /:/, $t, -1];
    pop @$path if @$path and $path->[-1] eq '';
    my $task = CTX->get_task($path);
    return $task ? $task->code : undef;
}

sub get_task_list (;$) {
    my ($t) = @_;
    my $path = defined $t ? [split /:/, $t, -1] : [];
    pop @$path if @$path and $path->[-1] eq '';
    if (@$path) {
        my $task = CTX->get_task($path);
        return $task->tasks ? $task : undef;
    } else {
        return CTX;
    }
}

sub user () {
    return CTX->get_param('user') || real_user();
}

sub real_user () {
    my $user = qx{whoami};
    chomp $user;
    return $user;
}

sub load (@) {
    my ($role, $task, %opt) = @_;

    do {
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
        CTX->set_param($key => $opt{override_settings}->{$key});
    }
}

!!1;
