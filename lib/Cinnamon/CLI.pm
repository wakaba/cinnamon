package Cinnamon::CLI;
use strict;
use warnings;
use IO::Handle;
use Encode;
use Getopt::Long;
use Path::Class;
use Cinnamon::Context;
use Cinnamon::LocalContext;

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
        "c|config=s" => \$self->{config},
        "s|set=s"    => sub {
            my ($key, $value) = split /=/, $_[1];
            ($self->{override_settings} ||= {})->{$key} = $value;
        },
        "I|ignore-errors" => \$self->{ignore_errors},
        "key-chain-fds=s" => \(my $key_chain_fds),
        "no-color"        => \(my $no_color),
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

    my $req_ctc;
    my $role = shift @ARGV;
    my $tasks = [map { [split /\s+/, $_] } map { decode 'utf-8', $_ } @ARGV];
    if (not defined $role) {
        $role = '';
        @$tasks = (['cinnamon:role:list']);
        $req_ctc = 1;
    } elsif (not @$tasks) {
        @$tasks = (['cinnamon:task:default']);
        $req_ctc = 1;
    }
    @$tasks = map { {name => $_->[0], args => [@$_[1..$#$_]]} } @$tasks;
    $role =~ s/^\@//;

    my $keychain;
    if ($key_chain_fds and $key_chain_fds =~ /^([0-9]+),([0-9]+)$/) {
        require Cinnamon::KeyChain::Pipe;
        $keychain = Cinnamon::KeyChain::Pipe->new_from_fds($1, $2);
    } else {
        require Cinnamon::KeyChain::CLI;
        $keychain = Cinnamon::KeyChain::CLI->new;
    }
    
    my $out;
    if (-t STDOUT) {
        require Cinnamon::OutputChannel::TTY;
        $out = Cinnamon::OutputChannel::TTY->new_from_fh(\*STDOUT);
        $out->no_color(1) if $no_color;
        STDOUT->autoflush(1);
    } else {
        require Cinnamon::OutputChannel::PlainText;
        $out = Cinnamon::OutputChannel::PlainText->new_from_fh(\*STDOUT);
        STDOUT->autoflush(1);
    }

    $hosts = [grep { length } split /\s*,\s*/, $hosts] if defined $hosts;

    my $user = qx{whoami};
    chomp $user;
    
    my $context = Cinnamon::Context->new(
        keychain => $keychain,
        output_channel => $out,
        operator_name => $user,
    );
    local $Cinnamon::Context::CTX = $context;
    local $Cinnamon::LocalContext = Cinnamon::LocalContext->new_from_global_context($context);
    $context->set_param(user => $self->{user}) if defined $self->{user};

    $Cinnamon::LocalContext->eval(sub {
        $context->load_config($self->{config});
    });
    for my $key (keys %{ $self->{override_settings} or {} }) {
        $context->set_param($key => $self->{override_settings}->{$key});
    }

    require Cinnamon::Task::Cinnamon if $req_ctc;
    my $error_occured = 0;
    for my $t (@$tasks) {
        my $result = $context->run(
            $role,
            $t->{name},
            hosts             => $hosts,
            args              => $t->{args},
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
    $msg .= qq{
Usage: $0 [--config=<path>] [--set=<parameter>] [--ignore-errors] [--help] [--version] <role> <task ...>
} if $args{help};
    $self->print($msg);
}

sub print {
    my ($self, $msg) = @_;
    print STDERR $msg;
}

!!1;
