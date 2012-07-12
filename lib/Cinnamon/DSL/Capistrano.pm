package Cinnamon::DSL::Capistrano;
use strict;
use warnings;
use Path::Class;
use Cinnamon::Runner;
use Cinnamon::Logger;
use Cinnamon::Config ();
use Cinnamon::DSL ();
use Cinnamon::DSL::Capistrano::Filter ();
use Exporter::Lite;

our @EXPORT;

push @EXPORT, qw(get);
sub get ($) {
    return &Cinnamon::DSL::get(@_);
}

push @EXPORT, qw(set);
sub set ($$) {
    my $name = $_[0];
    return &Cinnamon::DSL::set(@_);
}

push @EXPORT, qw(load);
sub load ($) {
    # XXX loop detection?
    my $recipe_f = file($_[0]); # XXX path resolution?
    Cinnamon::DSL::Capistrano::Filter->convert_and_run({
        file_name => $recipe_f->stringify,
    }, $recipe_f->slurp);
}

push @EXPORT, qw(after);
sub after ($$) {
    my ($task, $code) = @_;
    # XXX not implemented
}

push @EXPORT, qw(role);
sub role ($$;$) {
    &Cinnamon::DSL::role(@_);
}

our $Tasks = undef;

push @EXPORT, qw(namespace);
sub namespace ($$) {
    my ($name, $code) = @_;
    my $tasks = {};
    if ($Tasks) {
        if ($Tasks->{$name} and ref $Tasks->{$name} eq 'HASH') {
            $tasks = $Tasks->{$name};
        } else {
            $Tasks->{$name} = $tasks;
        }
    } else {
        my $current_task = Cinnamon::Config::get_task $name;
        if ($current_task and ref $current_task eq 'HASH') {
            $tasks = $current_task;
        }
    }
    {
        local $Tasks = $tasks;
        $code->();
    }
    unless ($Tasks) {
        &Cinnamon::DSL::task($name => $tasks);
    }
}

our $LastDesc = undef;

push @EXPORT, qw(desc);
sub desc ($) {
    my $name = shift;
    $LastDesc = $name;
}

push @EXPORT, qw(task);
sub task ($$) {
    my ($name, $code) = @_;
    if ($Tasks) {
        # XXX $LastDesc
        $Tasks->{$name} = $code;
    } else {
        &Cinnamon::DSL::task($name => $code, summary => $LastDesc);
    }
    undef $LastDesc;
}

push @EXPORT, qw(puts);
sub puts (@) {
    print @_, "\n";
}

our $Remote = {};

sub get_remote (;%) {
    my %args = @_;
    my $user = $args{user} || Cinnamon::DSL::get('user');
    my $host = $Cinnamon::Runner::Host; # XXX AE unsafe
    return $Remote->{$host}->{defined $args{user} ? $args{user} : ''} ||= do {
        log info => 'ssh ' . (defined $user ? "$user\@$host" : $host);

        Cinnamon::Remote->new(
            host => $host,
            user => $user,
        );
    };
}

push @EXPORT, qw(run);
sub run (@) {
    local $_ = get_remote;
    return Cinnamon::DSL::run_stream(@_);
}

push @EXPORT, qw(sudo);
sub sudo (@) {
    local $_ = get_remote;
    return Cinnamon::DSL::sudo_stream(@_);
}

push @EXPORT, qw(stream);
sub stream (@) {
    local $_ = get_remote;
    return Cinnamon::DSL::run_stream(@_);
}

push @EXPORT, qw(capture);
sub capture (@) {
    local $_ = get_remote;
    return Cinnamon::DSL::run(@_);
}

push @EXPORT, qw(system);
sub system (@) {
    local $_ = undef;
    return Cinnamon::DSL::run(@_);
}

push @EXPORT, qw(application);
sub application (@) {
    local $_ = undef;
    return Cinnamon::DSL::get 'application';
}

sub chomp {
    my (undef, $s) = @_;
    CORE::chomp $s;
    return $s;
}

sub define_method {
    my ($class, $name, $code) = @_;
    no strict 'refs';
    *{'Cinnamon::DSL::Capistrano::Filter::converted::'.$name} = $code;
}

1;
