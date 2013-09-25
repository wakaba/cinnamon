package Cinnamon::CLI;
use strict;
use warnings;
use Encode;
use Getopt::Long;
use Path::Class;
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
    my $help;
    my $version;
    my $hosts = $ENV{HOSTS};
    $p->getoptions(
        "u|user=s"   => \$self->{user},
        "h|help"     => \$help,
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
        "version" => \$version,
    );

    if ($help or $version) {
        $self->usage(help => $help, version => $version);
        return SUCCESS;
    }

    # check config exists
    $self->{config} ||= 'config/deploy.pl';
    if (!-e $self->{config}) {
        $self->print("cannot find config file for deploy : $self->{config}\n");
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
        @tasks = (['cinnamon:task:default']);
        $req_ctc = 1;
    }
    $role =~ s/^\@//;

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

    $context->load_config($self->{config});
    for my $key (keys %{ $self->{override_settings} or {} }) {
        $context->set_param($key => $self->{override_settings}->{$key});
    }

    if ($self->{info}) {
        $context->dump_info;
        return SUCCESS;
    }

    require Cinnamon::Task::Cinnamon if $req_ctc;
    my $error_occured = 0;
    for my $t (@tasks) {
        my $result = $context->run(
            $role,
            $t->[0],
            hosts             => $hosts,
            args              => [@$t[1..$#$t]],
        );
        $error_occured = 1 if $result->failed;
        last if ($error_occured && !$self->{ignore_errors});
        print "\n";
    }

    return $error_occured ? ERROR : SUCCESS;
}

sub git_log {
    return $_[0]->{git_log} ||= do {
        my $result = {};
        my $d = file(__FILE__)->dir->parent->parent;

        my $log = `cd \Q$d\E && git log -1 --raw`;
        if ($log =~ /^commit (\w+)/) {
            $result->{sha} = $1;
        }
        if ($log =~ /^Date:\s*(.+)/m) {
            $result->{date} = $1;
        }

        my $repo = `cd \Q$d\E && git config -f .git/config remote.origin.url`;
        my $gh_user;
        my $gh_name;
        if ($repo =~ m{^git\@github.com:([^./]+)/([^./]+)}) {
            $gh_user = $1;
            $gh_name = $2;
        } elsif ($repo =~ m{^git://github.com/([^./]+)/([^./]+)}) {
            $gh_user = $1;
            $gh_name = $2;
        } elsif ($repo =~ m{^https://github.com/([^./]+)/([^./]+)}) {
            $gh_user = $1;
            $gh_name = $2;
        }
        if (defined $result->{sha} and defined $gh_user) {
            $result->{rev_url} = qq{https://github.com/$gh_user/$gh_name/commit/$result->{sha}};
        }

        $result;
    };
}

sub usage {
    my ($self, %args) = @_;
    my $log = $self->git_log;
    my $msg = qq{Cinnamon ($log->{date})
@{[defined $log->{rev_url} ? "<$log->{rev_url}>" : "Revision $log->{sha}"]}
};
    $msg .= q{
Usage: cinnamon [--config=<path>] [--set=<parameter>] [--ignore-errors] [--help] [--info] <role> <task ...>
} if $args{help};
    $self->print($msg);
}

sub print {
    my ($self, $msg) = @_;
    print STDERR $msg;
}

!!1;
