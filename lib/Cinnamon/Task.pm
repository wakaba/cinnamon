package Cinnamon::Task;
use strict;
use warnings;
use Carp qw(croak);

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub name {
    return join ':', @{$_[0]->{path} or []};
}

sub code {
    if (@_ > 1) {
        $_[0]->{code} = $_[1];
    }
    return $_[0]->{code}; # or undef
}

sub is_callable {
    return !!$_[0]->{code};
}

sub tasks {
    return $_[0]->{tasks} ||= {};
}

sub has_subtasks {
    return !!(grep { $_ } values %{$_[0]->{tasks} or {}});
}

sub args {
    if (@_ > 1) {
        $_[0]->{args} = $_[1];
    }
    return $_[0]->{args}; # or undef
}

sub get_desc_with {
    my ($self, $local_context) = @_;
    my $desc = $self->{args}->{desc};
    if (defined $desc and ref $desc eq 'CODE') {
        return $local_context->eval($desc);
    } else {
        return $desc; # or undef
    }
}

sub run {
    my ($self, $local_context, %args) = @_;
    croak '|' . $self->name . '| is not callable' unless $self->is_callable;
    my $desc = $self->get_desc_with($local_context);
    $local_context->global->info(sprintf "call %s%s", $self->name, defined $desc ? " ($desc)" : '');

    my $hosts_option = $self->args->{hosts} || '';
    if ($hosts_option ne 'none') {
        my $hosts = $local_context->hosts;
        if (defined $args{role}) {
            my $desc = $args{role}->get_desc_with($local_context);
            $local_context->global->info(sprintf 'Host%s %s (@%s%s)',
                @$hosts == 1 ? '' : 's', (join ', ', @$hosts),
                $args{role}->name,
                defined $desc ? ' ' . $desc : '');
        } else {
            $local_context->global->info(sprintf 'Host%s %s',
                @$hosts == 1 ? '' : 's', (join ', ', @$hosts));
        }
    } elsif (defined $args{role}) {
        my $desc = defined $args{role}
            ? $args{role}->get_desc_with($local_context)
            : undef;
        $local_context->global->info(sprintf '(@%s%s)',
            $args{role}->name, defined $desc ? ' ' . $desc : '');
    }

    if ($hosts_option eq 'all' or $hosts_option eq 'none') {
        local $_ = undef;
        my $result = eval { $local_context->eval(sub { $self->code->($local_context) }) };
        
        if ($@) {
            chomp $@;
            my $msg = sprintf '%s %s', $self->name, $@;
            ($args{onerror} || sub { die $_[0] })->($msg);
            return $local_context->create_result(failed => 1);
        }

        if (UNIVERSAL::isa ($result, 'AnyEvent::CondVar')) {
            $result = $result->recv;
        } elsif (UNIVERSAL::isa ($result, 'Cinnamon::TaskResult')) {
            #
        } else {
            $local_context->global->error('A non-result non-cv object (.$result.) is retuned');
            $result = $local_context->create_result(failed => 1);
        }

        return $result;
    } else {
        my @succeeded_host;
        my @failed_host;
        my $skip_by_error;
        my $return = {};
        for my $host (@{$local_context->hosts}) {
            if ($skip_by_error) {
                my $msg = sprintf '%s [%s] %s', $self->name, $host, 'Skipped';
                ($args{onerror} || sub { die $_[0] })->($msg);
                push @failed_host, $host;
                next;
            }

            my $lc = $local_context->clone_for_task([$host], $local_context->args);
            local $_ = undef;
            #$lc->add_terminate_handler(sub {
            #  # XXX
            #});
            $return->{$host} = eval { $lc->eval(sub { $self->code->($host, @{$lc->args}) }) };
            
            if ($@) {
                chomp $@;
                my $msg = sprintf '%s [%s] %s', $self->name, $host, $@;
                ($args{onerror} || sub { die $_[0] })->($msg);
                push @failed_host, $host;
                $skip_by_error = 1;
            } else {
                push @succeeded_host, $host;
            }
        }
        return $local_context->create_result(
            succeeded_hosts => \@succeeded_host,
            failed_hosts => \@failed_host,
            return_values => $return,
        );
    }
}

1;
