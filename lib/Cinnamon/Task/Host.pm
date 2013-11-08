package Cinnamon::Task::Host;
use strict;
use warnings;
use Cinnamon::DSL;

task host => {
    name => (taskdef {
        my $state = shift;
        my $cv = $state->create_result_cv;
        for my $host (@{$state->hosts}) {
            $cv->begin_host($host);
            $state->remote(host => $host)->run_as_cv('hostname')->cb(sub {
                $cv->end_host($host, $_[0]->recv);
            });
        }
        return $cv->return;
    } {hosts => 'all'}),
};

!!1;
