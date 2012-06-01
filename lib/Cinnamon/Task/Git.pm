package Cinnamon::Task::Git;
use strict;
use warnings;
use Cinnamon::DSL;

task git => {
    update => sub {
        my ($host, @args) = @_;
        remote {
            my $dir = get 'deploy_dir';
            my $url = get 'git_repository';
            run_stream "git clone $url $dir || (cd $dir && git pull)";
            run_stream "cd $dir && git submodule update --init";
        } $host, user => get 'git_clone_user';
    },
};

!!1;
