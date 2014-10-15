#!/bin/sh
echo "1..1"

basedir=$(dirname $0)/..

ls $basedir/lib/Cinnamon/Task/*.pm | \
xargs -l1 -i% \
$basedir/perl -MCinnamon::Context -MCinnamon::LocalContext \
    -e '$g = Cinnamon::Context->new; $Cinnamon::LocalContext = Cinnamon::LocalContext->new_from_global_context ($g); print STDERR "# %..."; require "%"; print STDERR " OK\n"' && echo "ok 1"
