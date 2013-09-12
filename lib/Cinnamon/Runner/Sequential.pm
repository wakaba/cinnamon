package Cinnamon::Runner::Sequential;
use strict;
use warnings;
use Cinnamon::Runner;
push our @ISA, qw(Cinnamon::Runner);

use Cinnamon::Logger;
use Cinnamon::Config;

sub start {
    my ($class, $hosts, $task, @args) = @_;

    my %result;
    my $skip_by_error;
    for my $host (@$hosts) {
        if ($skip_by_error) {
            log error => sprintf '[%s] Skipped', $host;
            $result{$host}->{error}++;
            next;
        }

        $result{$host} = +{ error => 0 };

        local $Cinnamon::Runner::Host = $host; # XXX AE unsafe
        eval { $task->code->($host, @args) };

        if ($@) {
            chomp $@;
            log error => sprintf '[%s] %s', $host, $@;
            $result{$host}->{error}++;
            $skip_by_error = 1;
        }
    }

    return \%result;
}

!!1;
