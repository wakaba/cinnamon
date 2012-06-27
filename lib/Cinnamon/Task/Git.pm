package Cinnamon::Task::Git;
use strict;
use warnings;
use Cinnamon::DSL;
use Cinnamon::Logger;
use Exporter::Lite;

our @EXPORT;

push @EXPORT, qw(get_git_revision);
sub get_git_revision {
    if ($_ and $_->isa('Cinnamon::Remote')) {
        my $dir = get 'deploy_dir';
        my ($rev) = run "cd $dir && git rev-parse HEAD";
        chomp $rev;
        return $rev; # or undef
    } else {
        my ($rev) = run qw(git rev-parse HEAD);
        chomp $rev;
        return $rev; # or undef
    }
}

task git => {
    update => sub {
        my ($host, @args) = @_;
        my $result = {};
        my $local_rev = get_git_revision;
        remote {
            my $dir = get 'deploy_dir';
            my $url = get 'git_repository';
            $result->{old_revision} = get_git_revision; # or undef
            run_stream "git clone $url $dir || (cd $dir && git pull)";
            run_stream "cd $dir && git submodule update --init";
            $result->{new_revision} = get_git_revision; # or undef
        } $host, user => get 'git_clone_user';

        if ($result->{new_revision} ne $local_rev) {
            log error => sprintf "Remote revision is %s (local is %s)",
                (substr $result->{new_revision}, 0, 10),
                (substr $local_rev, 0, 10);
        }

        return $result;
    },
};

!!1;
