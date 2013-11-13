package Cinnamon::LocalContext;
use strict;
use warnings;

sub new_from_global_context {
    return bless {global_context => $_[1]}, $_[0];
}

sub clone_with_command_executor {
    return bless {%{$_[0]}, command_executor => $_[1]}, ref $_[0];
}

sub global {
    return $_[0]->{global_context};
}

sub keychain {
    return $_[0]->global->keychain;
}

sub command_executor {
    return $_[0]->{command_executor} ||= $_[0]->global->get_command_executor(local => 1);
}

sub output_channel {
    return $_[0]->global->output_channel;
}

sub get_param {
    my ($self, $name, @args) = @_;
    my $value = $self->global->params->{$name};
    $value = $self->eval(sub { $value->(@args) }) if ref $value eq 'CODE';
    return $value;
}

sub get_role_desc_by_name {
    my ($self, $role_name) = @_;
    my $code = $self->get_param('get_role_desc_for');
    return undef unless defined $code;
    return $self->eval(sub { $code->($role_name) });
}

sub eval {
    local $Cinnamon::LocalContext = $_[0];
    return $_[1]->();
}

1;
