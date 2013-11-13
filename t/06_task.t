use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->file('lib')->stringify;

use base qw(Test::Class);
use Test::More;

use Cinnamon::Task;

sub dummy : Test(1) {
    ok 1;
}

__PACKAGE__->runtests;
