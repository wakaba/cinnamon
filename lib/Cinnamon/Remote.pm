package Cinnamon::Remote;
use strict;
use warnings;
use Net::OpenSSH;
use Cinnamon::Logger;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub connection {
    my $self = shift;
       $self->{connection} ||= Net::OpenSSH->new(
           $self->{host}, user => $self->{user}
       );
}

sub host { $_[0]->{host} }

sub user { $_[0]->{user} }

sub execute {
    my ($self, @cmd) = @_;
    my $opt = shift @cmd;
    my ($stdout, $stderr);
    if (defined $opt && $opt->{sudo}) {
        ($stdout, $stderr) = $self->execute_by_sudo($opt->{password}, @cmd);
    }
    else {
        ($stdout, $stderr) = $self->connection->capture2(join(' ', @cmd));
    }

    +{
        stdout    => $stdout,
        stderr    => $stderr,
        has_error => !!$self->connection->error,
        error     => $self->connection->error,
    };
}

sub execute_by_sudo {
    my ($self, $password, @cmd) = @_;
    return $self->connection->capture2(
        { stdin_data => "$password\n" },
        join(' ', 'sudo', '-Sk', @cmd),
    );
}

sub execute_with_stream {
    my ($self, @cmd) = @_;
    my $opt = shift @cmd;

    if (defined $opt && $opt->{sudo}) {
        if (@cmd == 1 and $cmd[0] =~ m{[ &<>|]}) {
            @cmd = ('sudo', -Sk, '--', 'sh', -c => @cmd);
        } else {
            @cmd = ('sudo', '-Sk', '--', @cmd);
        }
    } else {
        if (@cmd == 1 and $cmd[0] =~ m{[ &<>|]}) {
            @cmd = ('sh', -c => @cmd);
        }
    }

    my $command = join ' ', map { quotemeta } @cmd;
    #log info => $command;
    my ($stdin, $stdout, $stderr, $pid) = $self->connection->open_ex({
        stdin_pipe => 1,
        stdout_pipe => 1,
        stderr_pipe => 1,
        tty => $opt->{tty},
    }, $command);

    if (defined $opt && $opt->{sudo}) {
        print $stdin "$opt->{password}\n";
    }

    +{
        stdin     => $stdin,
        stdout    => $stdout,
        stderr    => $stderr,
        pid       => $pid,
        has_error => !!$self->connection->error,
        error     => $self->connection->error,
    };
}

sub DESTROY {
    my $self = shift;
       $self->{connection} = undef;
}

!!1;
