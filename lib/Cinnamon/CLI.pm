package Cinnamon::CLI;
use strict;
use warnings;
use Encode;
use Getopt::Long;
use Cinnamon;

sub new {
    my $class = shift;
    bless { }, $class;
}

sub cinnamon {
    my $self = shift;
    $self->{cinnamon} ||= Cinnamon->new;
}

sub run {
    my ($self, @args) = @_;

    local @ARGV = @args;
    my $p = Getopt::Long::Parser->new(
        config => ["no_ignore_case", "pass_through"],
    );
    my $hosts = $ENV{HOSTS};
    $p->getoptions(
        "u|user=s"   => \$self->{user},
        "h|help"     => \$self->{help},
        "hosts=s"    => \$hosts,
        "i|info"     => \$self->{info},
        "c|config=s" => \$self->{config},
        "s|set=s"    => \$self->{override_settings},
        "I|ignore-errors" => \$self->{ignore_errors},
        "key-chain-fds=s" => \(my $key_chain_fds),
    );
    return $self->usage if $self->{help};

    $self->{config} ||= 'config/deploy.pl';
    if (!-e $self->{config}) {
        $self->print("cannot find config file for deploy : $self->{config}\n");
        return $self->usage;
    }

    my $role = shift @ARGV;
    my @tasks = map { [split /\s+/, $_] } map { decode 'utf-8', $_ } @ARGV;
    if (not defined $role) {
        require Cinnamon::Task::Cinnamon;
        $role = '';
        @tasks = (['cinnamon:role:list']);
    } elsif (not @tasks) {
        require Cinnamon::Task::Cinnamon;
        @tasks = (['cinnamon:task:list']);
    }

    my $keychain;
    if ($key_chain_fds and $key_chain_fds =~ /^([0-9]+),([0-9]+)$/) {
        require Cinnamon::KeyChain::Pipe;
        $keychain = Cinnamon::KeyChain::Pipe->new_from_fds($1, $2);
    } else {
        require Cinnamon::KeyChain::CLI;
        $keychain = Cinnamon::KeyChain::CLI->new;
    }
    
    if (defined $hosts) {
        $hosts = [grep { length } split /\s*,\s*/, $hosts];
    }
    
    for my $t (@tasks) {
        my ($success, $error) = $self->cinnamon->run(
            $role,
            $t->[0],
            config            => $self->{config},
            override_settings => $self->{override_settings},
            info              => $self->{info},
            user              => $self->{user},
            keychain          => $keychain,
            hosts             => $hosts,
            args              => [@$t[1..$#$t]],
        );
        last if (!defined $success || $self->{info});
        last if ($error && @$error > 0 && !$self->{ignore_errors});
        print "\n";
    }
}

sub usage {
    my $self = shift;
    my $msg = <<"HELP";
Usage: cinnamon [--config=<path>] [--help] [--info] <role> <task ...>
HELP
    $self->print($msg);
}

sub print {
    my ($self, $msg) = @_;
    print STDERR $msg;
}

!!1;
