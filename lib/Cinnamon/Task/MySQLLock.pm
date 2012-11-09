package Cinnamon::Task::MySQLLock;
use strict;
use warnings;
use Exporter::Lite;

our @EXPORT = qw(mysql_lock);

sub mysql_lock ($$) {
    return Cinnamon::Task::MySQLLock::Object->new_from_dsn_and_name(@_);
}

package Cinnamon::Task::MySQLLock::Object;
use Cinnamon::Logger;

sub new_from_dsn_and_name {
    my $self = bless {dsn => $_[1], name => $_[2]}, $_[0];
    $self->_lock;
    return $self;
}

sub dbh {
    require DBI;
    my $self = shift;
    return $self->{dbh} ||= DBI->connect($self->{dsn}, undef, undef, {
        RaiseError => 1,
    });
}

sub timeout {
    return 60*5;
}

sub _lock {
    my $self = shift;
    log info => 'SELECT GET_LOCK(?, ?), ' . $self->{name} . ', ' . $self->timeout;
    my $sth = $self->dbh->prepare('SELECT GET_LOCK(?, ?)');
    $sth->execute($self->{name}, $self->timeout);
}

sub _release {
    my $self = shift;
    log info => 'SELECT RELEASE_LOCK(?), ' . $self->{name};
    my $sth = $self->dbh->prepare('SELECT RELEASE_LOCK(?)');
    $sth->execute($self->{name});
}

sub DESTROY {
    my $self = shift;
    $self->_release;
}

1;
