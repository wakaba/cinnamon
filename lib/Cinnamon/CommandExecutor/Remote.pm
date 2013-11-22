package Cinnamon::CommandExecutor::Remote;
use strict;
use warnings;
use Cinnamon::CommandExecutor;
push our @ISA, qw(Cinnamon::CommandExecutor Cinnamon::Remote);
use Net::OpenSSH;
use AnyEvent;
use AnyEvent::Util;
use AnyEvent::Handle;
use POSIX;
use Cinnamon::CommandResult;
use Cinnamon::OutputChannel::LinedStream;
use Cinnamon::Config::User;

my $ConnectedSomewhere;

sub connection {
    my $self = shift;
       $self->{connection} ||= Net::OpenSSH->new(
           $self->{host}, user => $self->{user},
           async => 1,
       );
}

sub host { $_[0]->{host} || die "Host is not set" }

sub execute_as_cv {
    my ($self, $local_context, $commands, $opts) = @_;
    my $cv = AE::cv;

    my $cv_pre = AE::cv;
    my $pre_command = get_user_config 'ssh.pre_command';
    if (defined $pre_command) {
        unless ($ConnectedSomewhere) {
            $self->ui->push_action(sub {
                my $done = $_[0];
                (run_cmd $pre_command)->cb(sub {
                     $done->();
                     $cv_pre->send;
                 });
            });
            $ConnectedSomewhere = 1;
        } else {
            $self->ui->push_action(sub {
                $_[0]->();
                $cv_pre->send;
            });
        }
    } else {
        $cv_pre->send();
    }

    my $start_time = time;
    my $conn_cv = AE::cv;
    $cv_pre->cb(sub{
        my $conn = $self->connection;
        my $timer; $timer = AE::timer 0, 0.0010, sub {
            if ($conn->wait_for_master(1)) {
                $conn_cv->send($conn);
                undef $timer;
            } else {
                if ($conn->error) {
                    $local_context->global->error(sprintf "[%s] %s", $self->host, $conn->error);
                    $cv->send(Cinnamon::CommandResult->new(
                        host => $self->host,
                        has_error => 1,
                        error => -1,
                        error_msg => $conn->error,
                        start_time => $start_time,
                        end_time => time,
                        opts => $opts,
                    ));
                    undef $timer;
                }
            }
        };
    });

    $conn_cv->cb(sub {
        my $conn = $_[0]->recv;
        my $host = $self->host;
        my $user = $self->user;
        $user = defined $user ? $user . '@' : '';
        $local_context->global->info("[$user$host] \$ " . join ' ', @$commands);

        my ($stdin, $stdout, $stderr, $pid) = $conn->open3({
            tty => $opts->{tty},
        }, @$commands) or die "open3 failed: " . $conn->error;

        my $signal_error;
        $local_context->add_terminate_handler(my $handler = sub {
            kill $_[0]->{signal_name}, $pid;
            $signal_error = 1;
            return {die => 0, remove => 1};
        });

        my ($fhout, $fherr);
        my $stdout_str = '';
        my $stderr_str = '';

        $start_time = time;
        my $end = sub {
            undef $fhout;
            undef $fherr;
            waitpid $pid, 0;
            my $exitcode = $?;
            $local_context->remove_terminate_handler($handler);
            $cv->send(Cinnamon::CommandResult->new(
                host => $host,
                user => $user,
                start_time => $start_time,
                end_time => time,
                stdout    => $stdout_str,
                stderr    => $stderr_str,
                has_error => $exitcode > 0,
                error     => $exitcode,
                terminated_by_signal => $signal_error,
                opts => $opts,
            ));
        };

        if ($opts->{password}) {
            print $stdin "$opts->{password}\n";
        }

        my $out = $self->output_channel;
        my $out_logger = Cinnamon::OutputChannel::LinedStream->new_from_output_channel($out);
        $out_logger->class('info');
        $out_logger->label("$user$host o");
        my $err_logger = Cinnamon::OutputChannel::LinedStream->new_from_output_channel($out);
        $err_logger->class('error');
        $err_logger->label("$user$host e");
        my $print = $opts->{hide_output} ? sub { } : sub {
            my ($s, $handle) = @_;
            ($handle eq 'stdout' ? $out_logger : $err_logger)->print($s);
        };

        $fhout = AnyEvent::Handle->new(
            fh => $stdout,
            on_read => sub {
                $stdout_str .= $_[0]->rbuf;
                $print->($_[0]->rbuf => 'stdout');
                substr($_[0]->{rbuf}, 0) = '';
            },
            on_eof => sub {
                undef $stdout;
                $end->() if not $stdout and not $stderr;
            },
            on_error => sub {
                my ($handle, $fatal, $message) = @_;
                $local_context->global->error(sprintf "[%s o]: %s (%d)", $host, $message, $!)
                    unless $! == POSIX::EPIPE;
                undef $stdout;
                $end->() if not $stdout and not $stderr;
            },
        );

        $fherr = AnyEvent::Handle->new(
            fh => $stderr,
            on_read => sub {
                $stderr_str .= $_[0]->rbuf;
                $print->($_[0]->rbuf => 'stderr');
                substr($_[0]->{rbuf}, 0) = '';
            },
            on_eof => sub {
                undef $stderr;
                $end->() if not $stdout and not $stderr;
            },
            on_error => sub {
                my ($handle, $fatal, $message) = @_;
                $local_context->global->error(sprintf "[%s e]: %s (%d)", $host, $message, $!)
                    unless $! == POSIX::EPIPE;
                undef $stderr;
                $end->() if not $stdout and not $stderr;
            },
        );
    });

    return $cv;
}

# for backcompat
package Cinnamon::Remote;

!!1;
