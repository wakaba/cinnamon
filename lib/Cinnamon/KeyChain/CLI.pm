package Cinnamon::KeyChain::CLI;
use strict;
use warnings;
use AnyEvent;
use Term::ReadKey;

sub new {
    return bless {}, $_[0];
}

sub get_password_as_cv {
    my ($self, $user) = @_;
    my $cv = AE::cv;

    if (defined $self->{password}->{defined $user ? $user : ''}) {
        $cv->send($self->{password}->{defined $user ? $user : ''});
        return $cv;
    }

    local $| = 1;
    if (defined $user) {
        print "Enter sudo password for user $user: ";
    } else {
        print "Enter your sudo password: ";
    }
    ReadMode "noecho";
    chomp(my $password = ReadLine 0);
    ReadMode 0;
    print "\n";

    $cv->send($self->{password}->{defined $user ? $user : ''} = $password);
    return $cv;
}

1;
