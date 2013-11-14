package Cinnamon::CLI;
use strict;
use warnings;
use IO::Handle;
use Encode;
use Getopt::Long;
use Path::Class;
use Cinnamon::Role;
use Cinnamon::Task;
use Cinnamon::Context;
use Cinnamon::LocalContext;
use Cinnamon::DSL::TaskCalls;

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
        "key-chain-fds=s" => \(my $key_chain_fds),
        "no-color"        => \(my $no_color),
        "version" => \$version,
    );

    if ($help or $version) {
        $self->usage(help => $help, version => $version);
        return SUCCESS;
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

    # check config exists
    $self->{config} ||= 'config/deploy.pl';
    if (!-e $self->{config}) {
        $out->print("cannot find config file for deploy : $self->{config}", newline => 1, class => 'error');
        return ERROR;
    }

    my $role_name = shift @ARGV;
    my $tasks = [map { [split /\s+/, $_] } map { decode 'utf-8', $_ } @ARGV];
    my $role;
    if (not defined $role_name) {
        $role_name = '';
        $role = Cinnamon::Role->new(name => '', hosts => []);
        @$tasks = (['cinnamon:role:list']);
    } elsif (not @$tasks) {
        @$tasks = (['cinnamon:task:default']);
    }
    $role_name =~ s/^\@//;

    my $keychain;
    if ($key_chain_fds and $key_chain_fds =~ /^([0-9]+),([0-9]+)$/) {
        require Cinnamon::KeyChain::Pipe;
        $keychain = Cinnamon::KeyChain::Pipe->new_from_fds($1, $2);
    } else {
        require Cinnamon::KeyChain::CLI;
        $keychain = Cinnamon::KeyChain::CLI->new;
    }

    $hosts = [grep { length } split /\s*,\s*/, $hosts] if defined $hosts;

    my $user = qx{whoami};
    chomp $user;
    
    my $context = Cinnamon::Context->new(
        keychain => $keychain,
        output_channel => $out,
        operator_name => $user,
    );
    my $lc = Cinnamon::LocalContext->new_from_global_context($context);
    $context->set_param(user => $self->{user}) if defined $self->{user};

    $lc->eval(sub { $context->load_config($self->{config}) });
    for my $key (keys %{ $self->{override_settings} or {} }) {
        $context->set_param($key => $self->{override_settings}->{$key});
    }

    $role ||= $context->get_role($role_name);
    unless ($role) {
        $out->print("Role |\@$role_name| is not defined", newline => 1, class => 'error');
        return ERROR;
    }

    for (@$tasks) {
        my ($task_path, @args) = @$_;
        my $show_tasklist = $task_path =~ /:$/;
        $lc->eval(sub { require Cinnamon::Task::Cinnamon })
            if $task_path =~ /^cinnamon:/;
        my $task = $context->get_task($task_path);
        unless (defined $task) {
            $out->print("Task |$task_path| is not defined", newline => 1, class => 'error');
            return ERROR;
        }
        if ($show_tasklist or not $task->is_callable) {
            unshift @args, $task_path;
            $task_path = 'cinnamon:task:default';
            $lc->eval(sub { require Cinnamon::Task::Cinnamon });
            $task = $context->get_task($task_path);
        }
        $_ = {task => $task, args => \@args};
    }

    my ($task, $args) = @$tasks == 1
        ? ($tasks->[0]->{task}, $tasks->[0]->{args})
        : (Cinnamon::Task->new(
              code => Cinnamon::DSL::TaskCalls->get_code($tasks),
          ), []);
    $context->set_params_by_role($role);
    $context->set_param(task => $task->name);
    $hosts ||= $role->get_hosts_with($lc);
    my $result = $task->run(
        $lc->clone_for_task($hosts, $args),
        role => $role,
        onerror => sub {
            $out->print($_[0], newline => 1, class => 'error');
        },
    );

    if ($result->failed) {
        $out->print("Failed", newline => 1, class => 'error');
        $out->print("[OK] @{[join ', ', @{$result->succeeded_hosts}]}", newline => 1)
            if @{$result->succeeded_hosts};
        $out->print("[NG] @{[join ', ', @{$result->failed_hosts}]}", newline => 1, class => 'error')
            if @{$result->failed_hosts};
    } else {
        $out->print("Done", newline => 1, class => 'success');
        $out->print("[OK] @{[join ', ', @{$result->succeeded_hosts}]}", newline => 1, class => 'success')
            if @{$result->succeeded_hosts};
        $out->print("[NG] @{[join ', ', @{$result->failed_hosts}]}", newline => 1)
            if @{$result->failed_hosts};
    }

    return $result->failed ? ERROR : SUCCESS;
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
Usage: $0 [--config=<path>] [--set=<parameter>] [--help] [--version] <role> <task ...>
} if $args{help};
    $self->print($msg);
}

sub print {
    my ($self, $msg) = @_;
    print STDERR $msg;
}

!!1;
