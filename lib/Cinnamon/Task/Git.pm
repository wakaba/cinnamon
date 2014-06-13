package Cinnamon::Task::Git;
use strict;
use warnings;
use Path::Class;
use Cinnamon::DSL;
use Exporter::Lite;

our @EXPORT;

push @EXPORT, qw(get_git_revision);
sub get_git_revision ($) {
    my $git = $_[0];
    if ($_ and $_->isa('Cinnamon::CommandExecutor::Remote')) {
        my $dir = (get 'git_deploy_dir') || (get 'deploy_dir');
        my ($rev) = run "(cd $dir && $git rev-parse HEAD) || true";
        chomp $rev;
        return $rev || undef;
    } else {
        my ($rev) = run qw(sh -c), q(git rev-parse HEAD || true);
        chomp $rev;
        return $rev || undef;
    }
}

task git => {
    update => sub {
        my ($host, @args) = @_;
        my $result = {};
        my $git = (get 'git_path') || 'git';
        my $local_rev = get_git_revision (undef);
        my $branch = (get 'git_branch') || 'master';
        if (get 'git_use_current_branch') {
            ($branch) = run qw(sh -c), q(git name-rev --name-only HEAD || true);
            chomp $branch;
            $branch =~ s/~\d+$//;
            $branch = 'master' unless defined $branch and length $branch;
        }
        $branch =~ s{^origin/}{};
        $result->{branch} = $branch;
        remote {
            my $dir = (get 'git_deploy_dir') || (get 'deploy_dir');
            my $url = get 'git_repository';
            $result->{old_revision} = get_git_revision ($git); # or undef

            if (get 'git_pull_by_rsync') {
                my $path = get 'git_repository_path';
                run "mkdir -p $dir/.git";
                run "rsync -az $path/ $dir/.git";
                run "git config -f $dir/.git/config core.bare false";
                run "cd $dir && $git remote add origin $url";
                run "cd $dir && $git config branch.$branch.remote origin";
                run "cd $dir && $git config branch.$branch.merge refs/heads/$branch";
                run "cd $dir && (($git checkout $branch || ($git reset --hard && $git checkout $branch)) || $git checkout -b $branch origin/$branch) && $git reset --hard && $git pull origin $branch";
                run "cd $dir && $git submodule init && $git submodule sync && $git submodule update";
            } else {
                run_stream "$git clone $url $dir || (cd $dir && $git fetch)";
                run_stream "cd $dir && ($git checkout $branch || (($git pull || $git pull) && $git checkout -b $branch origin/$branch)) && ($git pull || $git pull)";
                run_stream "cd $dir && $git submodule init && $git submodule sync && $git submodule update";
            }

            $result->{new_revision} = get_git_revision ($git); # or undef
        } $host, user => get 'git_clone_user';

        if ($result->{new_revision} ne $local_rev) {
            log error => sprintf "Remote revision is %s (local is %s)",
                (substr $result->{new_revision}, 0, 10),
                (substr $local_rev || '', 0, 10);
            $result->{error}->{revision_mismatch} = 1;
        }

        return $result;
    },
    checkout => sub {
        my ($host, $rev, @args) = @_;
        my $result = {};
        die "Usage: checkout /revision/\n" unless $rev;
        my $exact = $rev =~ s/^=//;
        my $git = (get 'git_path') || 'git';
        remote {
            my $dir = (get 'git_deploy_dir') || (get 'deploy_dir');
            my $url = get 'git_repository';
            $result->{old_revision} = get_git_revision ($git); # or undef
            if ($result->{old_revision} and not $exact) {
                my ($newer) = run "(cd \Q$dir\E && $git rev-list HEAD | grep \Q$rev\E > /dev/null && echo 1) || echo 0";
                chomp $newer;
                if ($newer) {
                    warn "Remote commit ($result->{old_revision}) is newer; skipped\n";
                    $result->{new_revision} = $result->{old_revision};
                    $result->{error}->{older} = 1;
                    return;
                }
            }
            run_stream "$git clone $url $dir || (cd $dir && ($git fetch || $git fetch))";
            run_stream "cd $dir && $git checkout \Q$rev\E";
            run_stream "cd $dir && $git submodule update --init";
            $result->{new_revision} = get_git_revision ($git); # or undef
        } $host, user => get 'git_clone_user';

        if (not $result->{error} and
            $result->{new_revision} ne $rev and
            $result->{new_revision} !~ /^\Q$rev\E/) {
            log error => sprintf "Remote revision is %s (expected is %s)",
                (substr $result->{new_revision}, 0, 10),
                (substr $rev || '', 0, 10);
            $result->{error}->{revision_mismatch} = 1;
        }

        return $result;
    },
    show_revision => sub {
        my ($host, $file_name, @args) = @_;
        my $git = (get 'git_path') || 'git';
        remote {
            if (defined $file_name) {
                my $f = file($file_name);
                $f->dir->mkpath;
                print { $f->openw } get_git_revision ($git);
            } else {
                print get_git_revision ($git);
            }
        } $host, user => get 'git_clone_user';
    },
    show_url => sub {
        my ($host, $file_name, @args) = @_;
        my $git = (get 'git_path') || 'git';
        remote {
            my $dir = get 'deploy_dir';
            run "cd \Q$dir\E && $git config remote.origin.url";
        } $host, user => get 'git_clone_user';
    },
    reset_hard => sub {
        my ($host, @args) = @_;
        my $git = (get 'git_path') || 'git';
        remote {
            my $dir = get 'deploy_dir';
            run "cd \Q$dir\E && $git add . && $git reset --hard";
        } $host, user => get 'git_clone_user';
    },
};

!!1;
