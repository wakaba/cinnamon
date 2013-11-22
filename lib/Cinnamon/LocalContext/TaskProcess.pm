package Cinnamon::LocalContext::TaskProcess;
use strict;
use warnings;
use Cinnamon::LocalContext;
push our @ISA, qw(Cinnamon::LocalContext);
use Carp qw(croak carp);
use Cinnamon::TPP;
use Cinnamon::CommandResult; # run_as_cv, sudo_as_cv
use Cinnamon::CommandExecutor::InTaskProcess;

my $bad_method = sub {
    die "This method can't be invoked in a task process";
};

sub clone_with_new_command_executor {
    my $self = shift;
    my $exec = Cinnamon::CommandExecutor::InTaskProcess->new(
        @_,
        output_channel => $self->output_channel,
    );
    return bless {%$self, command_executor => $exec}, ref $self;
}

sub in_task_process {
    return 1;
}

*global = $bad_method;

sub command_executor {
    return $_[0]->{command_executor} ||= Cinnamon::CommandExecutor::InTaskProcess->new(
        local => 1,
        output_channel => $_[0]->output_channel,
    );
}

*keychain = $bad_method;
*get_password_as_cv = $bad_method;

sub get_task {
    return shift->{global}->get_task(@_);
}

sub operator_name {
    return $_[0]->{global}->operator_name;
}

sub tpp_parent_fh {
    return $_[0]->{tpp_parent_fh};
}

sub tpp_parent_operation {
    my $fh = $_[0]->tpp_parent_fh;
    syswrite $fh, tpp_serialize $_[1];
    my $result = tpp_parse readline $fh;
    croak $result->{throw} if defined $result->{throw};
    return $result;
}

sub tpp_close {
    my $fh = $_[0]->tpp_parent_fh;
    syswrite $fh, tpp_serialize {type => 'end'};
}

sub invoke_in_main_process {
    my ($self, $args) = @_;
    my $result = $self->tpp_parent_operation({
        type => 'function',
        %$args,
    });
    for (@{$result->{return}}) {
        eval qq{ require @{[ref $_]} } if ref $_;
    }
    return $result;
}

sub run_as_cv {
    my ($self, $command, $opts) = @_;
    my $return = $self->tpp_parent_operation({
        type => 'run', command => $command, opts => $opts,
        command_executor_args => $self->command_executor->as_args,
    });
    return $return->{result};
}

sub sudo_as_cv {
    my ($self, $command, $opts) = @_;
    my $return = $self->tpp_parent_operation({
        type => 'run', command => $command, opts => {%$opts, sudo => 1},
        command_executor_args => $self->command_executor->as_args,
    });
    return $return->{result};
}

*fork_eval_as_cv = $bad_method;
*add_terminate_handler = $bad_method;
*remove_terminate_handler = $bad_method;
*process_terminate_handlers = $bad_method;
*destroy = $bad_method;
*context = $bad_method;
*remote = $bad_method;
*local = $bad_method;

our $OrigCV;

sub condvar (;&) {
    carp "AnyEvent cannot be used in tasks";
    return $OrigCV->($_[0]) if $_[0];
    return bless {}, 'Cinnamon::LocalContext::TaskProcess::CondVar';
}

package Cinnamon::LocalContext::TaskProcess::CondVar;

sub send {
    return $_[0]->{value} = $_[1];
}

sub recv {
    return $_[0]->{value};
}

1;
