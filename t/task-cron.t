#!/bin/sh
basedir=`dirname $0`/..
echo "1..1"
($basedir/perl -c $basedir/lib/Cinnamon/Task/Cron.pm && echo "ok 1") || echo "not ok 1"
