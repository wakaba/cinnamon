package Cinnamon::Task::AutoTest2013;
use strict;
use warnings;
use Cinnamon::Task::HTTP;
use Cinnamon::DSL;
use AnyEvent;
use Exporter::Lite;

our @EXPORT = qw(schedule_test);

sub schedule_test ($$$) {
    my ($repo, $branch, $rev) = @_;
    my $test_host = get 'autotest_host';
    my $cv = AE::cv;
    http_post_json
        url => qq<http://$test_host/jobs>,
        basic_auth => [api_key => get 'autotest_api_key'],
        content => {
            repository => {url => $repo},
            ref => (defined $branch ? 'refs/heads/' . $branch : undef),
            after => $rev,
        },
        anyevent => 1,
        cb => sub {
            my (undef, $res) = @_;
            die "Failed to insert test job\n" if $res->is_error;
            $cv->send;
        };
    $cv->recv;
}

task autotest2013 => {
    schedule => sub {
        my ($host, @args) = @_;
        my $rev = `git rev-parse HEAD` or die "Can't get git commit\n";
        chomp $rev;
        my $branch = `git branch`;
        if ($branch =~ /^\* (.+)$/m) {
            $branch = $1;
            undef $branch if $branch eq '(no branch)';
        } else {
            undef $branch;
        }
        my $repo = get 'git_repository';
        schedule_test $repo, $branch, $rev;
    },
};

1;
