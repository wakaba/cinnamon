package Cinnamon::LocalContext;
use strict;
use warnings;
use Scalar::Util qw(weaken);
use AnyEvent;
use AnyEvent::Util qw(portable_socketpair fork_call);
use AnyEvent::Handle;
use Cinnamon::TPP;
use Cinnamon::TaskResult;

sub new_from_global_context {
    return bless {global => $_[1], params => {}}, $_[0];
}

sub clone_for_task {
    return bless {
        %{$_[0]},
        command_executor => undef,
        hosts => $_[1],
        args => $_[2],
    }, ref $_[0];
}

sub clone_with_new_command_executor {
    my $self = shift;
    my $exec = $self->global->get_command_executor(@_);
    return bless {%$self, command_executor => $exec}, ref $self;
}

sub in_task_process {
    return 0;
}

sub global {
    return $_[0]->{global};
}

sub command_executor {
    return $_[0]->{command_executor} ||= $_[0]->global->get_command_executor(local => 1);
}

sub keychain {
    return $_[0]->global->keychain;
}

sub get_password_as_cv {
    return $_[0]->keychain->get_password_as_cv($_[0]->command_executor->user);
}

sub run_as_cv {
    my ($self, $commands, $opts) = @_;
    my $cv = AE::cv;
    my $executor = $self->command_executor;
    $commands = $executor->construct_command($commands, $opts);
    $executor->execute_as_cv($self, $commands, $opts)->cb(sub {
        my $result = $_[0]->recv;
        $result->show_result_and_detect_error($self->global);
        $cv->send($result);
    });
    return $cv;
}

sub sudo_as_cv {
    my ($self, $commands, $opts) = @_;
    my $cv = AE::cv;
    $self->get_password_as_cv->cb(sub {
        $opts->{sudo} = 1;
        $opts->{password} = $_[0]->recv;
        $self->run_as_cv($commands, $opts)->cb(sub { $cv->send($_[0]->recv) });
    });
    return $cv;
}

sub output_channel {
    return $_[0]->{output_channel} || $_[0]->global->output_channel;
}

sub params {
    return $_[0]->{params};
}

sub set_param {
    my ($self, $key, $value) = @_;
    $self->params->{$key} = $value;
}

sub set_params_by_role {
    my ($self, $role) = @_;
    my $params = $role->params;
    $self->set_param(role => $role->name);
    $self->set_param($_ => $params->{$_}) for keys %$params;
}

sub get_param {
    my ($self, $name, @args) = @_;
    my $value = $self->params->{$name};
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

sub fork_eval_as_cv {
    my ($self, $code) = @_;
    my $cv = AE::cv;
    my ($fh_child, $fh_parent) = portable_socketpair;
    my $process_line;
    my $_process_line;
    my $child; $child = AnyEvent::Handle->new(
        fh => $fh_child,
        on_eof => sub {
            undef $child;
            undef $_process_line;
        },
        on_error => sub {
            if ($_[1]) {
                $self->global->error($_[2]);
                undef $child;
                undef $_process_line;
            }
        },
    );
    $_process_line = sub {
        my $data = tpp_parse $_[1];
        if ($data->{type} eq 'run') {
            my $cv = AE::cv;
            if ($data->{opts}->{sudo}) {
                $self->get_password_as_cv->cb(sub {
                    $data->{opts}->{password} = $_[0]->recv;
                    $cv->send;
                });
            } else {
                $cv->send;
            }
            $cv->cb(sub {
                my $executor = $self->global->get_command_executor(%{$data->{command_executor_args}});
                $executor->execute_as_cv($self, $data->{command}, $data->{opts})->cb(sub {
                    my $result = $_[0]->recv;
                    $result->show_result_and_detect_error($self->global);
                    $child->push_write (tpp_serialize {
                        result => $result,
                    }) if $child;
                });
            });
        } elsif ($data->{type} eq 'logger') {
            # XXX blocking
            $self->output_channel->print(
                $data->{message}, %{$data->{args}},
            );
            $child->push_write (tpp_serialize {});
        } elsif ($data->{type} eq 'function') {
            my $return;
            my $context = $data->{context} || '';
            my $async = $data->{async} || '';
            my @args = @{$data->{args}};
            push @args, cb => sub {
                $return = $context eq 'list' ? [@_] : $_[0];
                $child->push_write (tpp_serialize {return => $return});
            } if $async eq 'cb';
            if ($context eq 'list') {
                no strict 'refs';
                $return = eval { [&{$data->{name}}(@args)] };
            } else {
                no strict 'refs';
                $return = eval { &{$data->{name}}(@args) };
            }
            if ($@ or not $async eq 'cb') {
                my $result = $@ ? {throw => $@} : {return => $return};
                $child->push_write (tpp_serialize $result);
            }
        } elsif ($data->{type} eq 'end') {
            undef $_process_line;
            return;
        } else {
            $self->global->error("Broken data from task process: |$data->{type}|");
            undef $_process_line;
            return;
        }
        $child->push_read (line => $process_line);
    };
    $process_line = sub {
        my @args = @_;
        $self->eval(sub { $_process_line->(@args) });
    };
    $child->push_read (line => $process_line);

    # XXX concur=only|serial|auto|all
    fork_call {
        local $SIG{INT} = sub { warn "SIGINT received\n"; exit 1 };
        local $SIG{TERM} = sub { warn "SIGTERM received\n"; exit 1 };
        close $fh_child;
        $child->destroy;
        require Cinnamon::LocalContext::TaskProcess;
        require Cinnamon::OutputChannel::TaskProcess;
        local *AnyEvent::condvar = \&Cinnamon::LocalContext::TaskProcess::condvar;
        $Cinnamon::LocalContext::TaskProcess::OrigCV = \&AE::cv;
        local *AE::cv = \&Cinnamon::LocalContext::TaskProcess::condvar;
        bless $Cinnamon::LocalContext, 'Cinnamon::LocalContext::TaskProcess';
        $Cinnamon::LocalContext->{tpp_parent_fh} = $fh_parent;
        local $Cinnamon::LocalContext->{output_channel} = Cinnamon::OutputChannel::TaskProcess->new_from_local_context($Cinnamon::LocalContext); # loop ref
        my $return = $code->();
        $Cinnamon::LocalContext->tpp_close;
        return $return;
    } sub {
        if ($@) {
            $self->output_channel->print($@, newline => 1, class => 'error');
            $cv->send({error => 1});
        } else {
            $cv->send({return_value => $_[0]});
        }
    };
    close $fh_parent;
    return $cv;
}

sub hosts {
    return $_[0]->{hosts} || [];
}

sub args {
    return $_[0]->{args} || [];
}

sub create_result {
    my ($self, %args) = @_;
    return Cinnamon::TaskResult->new(
        failed => defined $args{failed} ? $args{failed} : !!@{$args{failed_hosts} or []},
        succeeded_hosts => $args{succeeded_hosts},
        failed_hosts => $args{failed_hosts},
        return_values => $args{return_values},
    );
}

sub create_result_cv {
    my $self = shift;
    return $self->create_result(@_)->as_cv;
}

sub add_terminate_handler {
    my ($self, $code) = @_;
    weaken ($self = $self);
    $self->{SIGTERM} ||= AE::signal TERM => sub {
        my $t; $t = AE::timer 0, 0, sub {
            $self->global->error('SIGTERM received');
            $self->process_terminate_handlers({signal_name => 'TERM'});
            undef $t;
        };
    };
    $self->{SIGINT} ||= AE::signal INT => sub {
        my $t; $t = AE::timer 0, 0, sub {
            $self->global->error('SIGINT received');
            $self->process_terminate_handlers({signal_name => 'INT'});
            undef $t;
        };
    };
    push @{$self->{terminate_handlers} ||= []}, $code;
}

sub remove_terminate_handler {
    my ($self, $code) = @_;
    $self->{terminate_handlers} = [grep { $_ ne $code } @{$self->{terminate_handlers} or []}];
    unless (@{$self->{terminate_handlers}}) {
        delete $self->{SIGTERM};
        delete $self->{SIGINT};
    }
}

sub process_terminate_handlers {
    my $self = shift;
    my $die;
    my @new;
    for (@{$self->{terminate_handlers} || []}) {
        my $result = $_->($_[0]);
        $die = 1 if $result->{die};
        push @new, $_ unless $result->{remove};
    }
    $self->{terminate_handlers} = \@new;
    die "Terminated by signal\n" if $die;
}

sub destroy {
    delete $_[0]->{SIGTERM};
    delete $_[0]->{SIGINT};
    delete $_[0]->{terminate_handlers};
}

# compat
*context = \&global;
sub remote {
    my ($self, %args) = @_;
    my $executor = $self->global->get_command_executor(%args, remote => 1);
    return $self->clone_with_command_executor($executor);
}
sub local {
    my ($self, %args) = @_;
    my $executor = $self->global->get_command_executor(%args, local => 1);
    return $self->clone_with_command_executor($executor);
}

1;
