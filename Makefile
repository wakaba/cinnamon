
all:

# ------ Setup ------

WGET = wget

local/bin/pmbp.pl: always
	mkdir -p local/bin
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/bin/pmbp.pl

local-perl: pmbp-install
pmb-update: pmbp-update
pmb-install: pmbp-install

pmbp-upgrade: local/bin/pmbp.pl
	perl local/bin/pmbp.pl --update-pmbp-pl

pmbp-update: pmbp-upgrade
	perl local/bin/pmbp.pl --update

pmbp-install: pmbp-upgrade
	perl local/bin/pmbp.pl --install \
	    --create-perl-command-shortcut perl \
	    --create-perl-command-shortcut prove

deps: pmbp-install

# ------ Tests ------

PROVE = ./prove

test: test-deps test-main

test-deps: deps

test-main:
	$(PROVE) t/*.t

always:
