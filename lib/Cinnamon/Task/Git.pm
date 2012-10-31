package Cinnamon::Task::Git;
use strict;
use warnings;
use Path::Class;
use Cinnamon::DSL;
use Cinnamon::Logger;
use Exporter::Lite;

our @EXPORT;

push @EXPORT, qw(get_git_revision);
sub get_git_revision {
    if ($_ and $_->isa('Cinnamon::Remote')) {
        my $dir = (get 'git_deploy_dir') || (get 'deploy_dir');
        my ($rev) = run "(cd $dir && git rev-parse HEAD) || true";
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
        my $local_rev = get_git_revision;
        remote {
            my $dir = (get 'git_deploy_dir') || (get 'deploy_dir');
            my $url = get 'git_repository';
            my $branch = (get 'git_branch') || 'master';
            $branch =~ s{^origin/}{};
            $result->{old_revision} = get_git_revision; # or undef
            run_stream "git clone $url $dir || (cd $dir && git fetch)";
            run_stream "cd $dir && (git checkout $branch || (git pull && git checkout -b $branch origin/$branch)) && git pull";
            run_stream "cd $dir && git submodule update --init";
            $result->{new_revision} = get_git_revision; # or undef
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
        remote {
            my $dir = (get 'git_deploy_dir') || (get 'deploy_dir');
            my $url = get 'git_repository';
            $result->{old_revision} = get_git_revision; # or undef
            if ($result->{old_revision} and not $exact) {
                my ($newer) = run "(cd \Q$dir\E && git rev-list HEAD | grep \Q$rev\E > /dev/null && echo 1) || echo 0";
                chomp $newer;
                if ($newer) {
                    warn "Remote commit ($result->{old_revision}) is newer; skipped\n";
                    $result->{new_revision} = $result->{old_revision};
                    $result->{error}->{older} = 1;
                    return;
                }
            }
            run_stream "git clone $url $dir || (cd $dir && git fetch)";
            run_stream "cd $dir && git checkout \Q$rev\E";
            run_stream "cd $dir && git submodule update --init";
            $result->{new_revision} = get_git_revision; # or undef
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
        remote {
            if (defined $file_name) {
                my $f = file($file_name);
                $f->dir->mkpath;
                print { $f->openw } get_git_revision;
            } else {
                print get_git_revision;
            }
        } $host;
    },
};

!!1;
