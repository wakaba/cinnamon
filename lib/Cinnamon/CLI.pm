package Cinnamon::CLI;
use strict;
use warnings;
use Encode;
use Getopt::Long;
use Cinnamon::Context;
use Cinnamon::Config;
use Cinnamon::Logger;

use constant { SUCCESS => 0, ERROR => 1 };

sub new {
    my $class = shift;
    bless { }, $class;
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
        "s|set=s"    => sub {
            my ($key, $value) = split /=/, $_[1];
            ($self->{override_settings} ||= {})->{$key} = $value;
        },
        "I|ignore-errors" => \$self->{ignore_errors},
        "key-chain-fds=s" => \(my $key_chain_fds),
        "no-color"        => \$self->{no_color},
    );

    # --help option
    if ($self->{help}) {
        $self->usage;
        return SUCCESS;
    }

    # check config exists
    $self->{config} ||= 'config/deploy.pl';
    if (!-e $self->{config}) {
        $self->print("cannot find config file for deploy : $self->{config}\n");
        $self->usage;
        return ERROR;
    }

    # check role and task exists
    my $req_ctc;
    my $role = shift @ARGV;
    my @tasks = map { [split /\s+/, $_] } map { decode 'utf-8', $_ } @ARGV;
    if (not defined $role) {
        $role = '';
        @tasks = (['cinnamon:role:list']);
        $req_ctc = 1;
    } elsif (not @tasks) {
        @tasks = (['cinnamon:task:list']);
        $req_ctc = 1;
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

    Cinnamon::Logger->init_logger(no_color => $self->{no_color});
    
    my $context = Cinnamon::Context->new(
        keychain => $keychain,
    );
    local $Cinnamon::Context::CTX = $context;
    $context->set_param(user => $self->{user}) if defined $self->{user};
    my $error_occured = 0;
    require Cinnamon::Task::Cinnamon if $req_ctc;
    for my $t (@tasks) {
        my ($success, $error) = $context->run(
            $role,
            $t->[0],
            config            => $self->{config},
            override_settings => $self->{override_settings},
            info              => $self->{info},
            hosts             => $hosts,
            args              => [@$t[1..$#$t]],
        );
        last if ($self->{info});

        # check execution error
        $error_occured ||= ! defined $success;
        $error_occured ||= scalar @$error > 0;

        last if ($error_occured && !$self->{ignore_errors});
        print "\n";
    }

    return $error_occured ? ERROR : SUCCESS;
}

sub usage {
    my $self = shift;
    my $msg = <<"HELP";
Usage: cinnamon [--config=<path>] [--set=<parameter>] [--ignore-errors] [--help] [--info] <role> <task ...>
HELP
    $self->print($msg);
}

sub print {
    my ($self, $msg) = @_;
    print STDERR $msg;
}

!!1;
