package Cinnamon::Config;
use strict;
use warnings;

sub set ($$) {
    $Cinnamon::Context::CTX->set_param(@_);
}

sub set_default ($$) {
    $Cinnamon::Context::CTX->set_param(@_) unless defined $Cinnamon::Context::CTX->get_param($_[0]);
}

sub get ($@) {
    return $Cinnamon::Context::CTX->get_param(@_);
}

sub set_role ($$$;%) {
    my ($role, $hosts, $params, %args) = @_;
    $Cinnamon::Context::CTX->set_role($role, $hosts, $params, \%args);
}

sub set_role_alias ($$) {
    $Cinnamon::Context::CTX->set_role_alias($_[0] => $_[1]);
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
    $name = [$name] unless ref $name eq 'ARRAY';
    _expand_tasks $name => $task_def => $defs, $root_args;
    $Cinnamon::Context::CTX->define_tasks($defs);
}

sub get_task ($) {
    my $task = $Cinnamon::Context::CTX->get_task($_[0]);
    return $task ? $task->code : undef;
}

sub user () {
    return $Cinnamon::Context::CTX->get_param('user') || real_user();
}

sub real_user () {
    my $user = qx{whoami};
    chomp $user;
    return $user;
}

!!1;
