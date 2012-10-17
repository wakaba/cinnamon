package Cinnamon::Task::Host;
use strict;
use warnings;
use Cinnamon::DSL;

task host => {
    name => sub {
        my ($host, @args) = @_;
        remote {
            run q<hostname>;
        } $host;
    },
};

!!1;
