package Cinnamon::DSL::TaskCalls;
use strict;
use warnings;

sub get_code {
    my $ops = $_[1];
    return sub {
        my $lc = $Cinnamon::LocalContext;
        for my $op (@$ops) {
            $lc->global->set_param(task => $op->{task}->name);
            my $result = $op->{task}->run(
                #role => ...,
                hosts => $lc->hosts,
                args => $op->{args},
                onerror => sub { die "$_[0]\n" },
                context => $lc->global,
            );
            die "Task |@{[$op->{task}->name]}| failed\n" if $result->failed;
            $lc->global->info('');
        }
    };
}

1;
