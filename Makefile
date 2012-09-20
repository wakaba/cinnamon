
all:

# ------ Setup ------

WGET = wget
PERL = perl
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120328

Makefile.setupenv:
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

lperl local-perl perl-version perl-exec \
pmb-update \
generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@ \
            REMOTEDEV_HOST=$(REMOTEDEV_HOST) \
            REMOTEDEV_PERL_VERSION=$(REMOTEDEV_PERL_VERSION) \
	    PMB_PMTAR_REPO_URL=$(PMB_PMTAR_REPO_URL) \
	    PMB_PMPP_REPO_URL=$(PMB_PMPP_REPO_URL)

CURL = curl
PMBP = $(PERL) local/bin/pmbp.pl

local/bin/pmbp.pl: always
	mkdir -p local/bin
	curl https://raw.github.com/wakaba/perl-setupenv/master/bin/pmbp.pl > $@

pmb-install: pmbp-install

pmbp-install: local/bin/pmbp.pl
	$(PMBP) --root-dir-name . \
	    --install-modules-by-list \
	    --write-libs-txt config/perl/libs.txt

deps: pmbp-install

# ------ Tests ------

PERL_ENV = PATH=$(PERL_PATH):$(PATH) PERL5LIB=$(shell cat config/perl/libs.txt)
PROVE = prove

test: test-deps test-main

test-deps: deps

test-main:
	$(PERL_ENV) $(PROVE) t/*.t

always:
