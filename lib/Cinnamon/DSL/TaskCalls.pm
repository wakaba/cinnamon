package Cinnamon::DSL::TaskCalls;
use strict;
use warnings;

sub get_code {
    my $ops = $_[1];
    return sub {
        my $lc = $Cinnamon::LocalContext;
        for my $op (@$ops) {
            $lc->set_param(task => $op->{task}->name);
            my $result = $op->{task}->run(
                $lc->clone_for_task($lc->hosts, $op->{args}),
                #role => ...,
                onerror => sub { die "$_[0]\n" },
            );
            die "Task |@{[$op->{task}->name]}| failed\n" if $result->failed;
            $lc->global->info('');
        }
    };
}

1;
