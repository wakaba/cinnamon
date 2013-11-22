package Cinnamon::KeyChain::CLI;
use strict;
use warnings;
use Encode;
use AnyEvent;
use Term::ReadKey;

sub new_from_ui {
    return bless {ui => $_[1]}, $_[0];
}

sub get_password_as_cv {
    my ($self, $user) = @_;
    my $cv = AE::cv;

    if (defined $self->{password}->{defined $user ? $user : ''}) {
        AE::postpone {
            $cv->send($self->{password}->{defined $user ? $user : ''});
        };
        return $cv;
    }

    $self->{ui}->push_action(sub {
        my $done = $_[0];
        ## XXX Blocking I/O
        local $| = 1;
        if (defined $user) {
            print "Enter sudo password for user $user: ";
        } else {
            print "Enter your sudo password: ";
        }
        ReadMode "noecho";
        chomp(my $password = decode 'utf-8', ReadLine 0);
        ReadMode 0;
        print "\n";

        $done->();
        $cv->send($self->{password}->{defined $user ? $user : ''} = $password);
    });
    return $cv;
}

1;
