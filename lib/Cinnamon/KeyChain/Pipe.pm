package Cinnamon::KeyChain::Pipe;
use strict;
use warnings;
use Encode;
use AnyEvent;
use AnyEvent::Handle;
use Scalar::Util qw(weaken);
use MIME::Base64 qw(encode_base64url decode_base64url);

sub new_from_fds {
    my ($class, $read_fd, $write_fd) = @_;
    
    open my $read_file, '<&' . $read_fd or die "$0: &$read_fd: $!";
    open my $write_file, '>&' . $write_fd or die "$0: &$write_fd: $!";

    my $read_handle; $read_handle = AnyEvent::Handle->new(
        fh => $read_file,
        on_error => sub {
            my ($hdl, $fatal, $msg) = @_;
            die "$0: &$read_fd: $msg\n" if $fatal;
            $hdl->destroy;
        },
    );
    my $write_handle; $write_handle = AnyEvent::Handle->new(
        fh => $write_file,
        on_error => sub {
            my ($hdl, $fatal, $msg) = @_;
            die "$0: &$write_fd: $msg\n" if $fatal;
            $hdl->destroy;
        },
    );

    return bless {
        read_handle => $read_handle,
        write_handle => $write_handle,
    }, $class;
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

    $user = defined $user ? encode_base64url encode 'utf-8', $user : '';
    $self->{write_handle}->push_write("password $user\n");
    weaken($self = $self);
    $self->{read_handle}->push_read(line => sub {
        if ($_[1] =~ /^password \Q$user\E (\S*)$/) {
            $cv->send($self->{password}->{defined $user ? $user : ''}
                          = decode 'utf-8', decode_base64url $1);
        }
    });

    return $cv;
}

1;
