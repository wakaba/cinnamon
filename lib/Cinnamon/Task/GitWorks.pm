package Cinnamon::Task::GitWorks;
use strict;
use warnings;
use Cinnamon::Task::HTTP;
use Cinnamon::DSL;
use AnyEvent;

task gitworks => {
    cennel => {
        add_operations => sub {
            my ($host, @args) = @_;
            my $gw_host = get 'gw_host';
            my $rev = `git rev-parse HEAD` or die "Can't get git commit\n";
            chomp $rev;
            my $branch = `git branch`;
            if ($branch =~ /^\* (.+)$/m) {
                $branch = $1;
                undef $branch if $branch eq '(no branch)';
            } else {
                undef $branch;
            }
            my $cv = AE::cv;
            http_post_json
                url => qq<http://$gw_host/hook>,
                basic_auth => [api_key => get 'gw_api_key'],
                content => {
                    repository => {url => get 'git_repository'},
                    ref => (defined $branch ? 'refs/heads/' . $branch : undef),
                    after => $rev,
                    hook_args => {
                        action_type => 'cennel.add-operations',
                        action_args => {},
                    },
                },
                anyevent => 1,
                cb => sub {
                    my (undef, $res) = @_;
                    die "Failed to insert cennel job\n" if $res->is_error;
                    $cv->send;
                };
            $cv->recv;
        },
    },
};

1;
