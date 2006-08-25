# $Id: Makefile,v 1.51 2006/08/25 16:20:31 dancy Exp $

ARCH=$(shell uname -i)

preferred_lisp?=/fi/cl/8.0/bin/mlisp
alt_lisp0=/usr/local/acl80/mlisp
alt_lisp1=/storage1/acl80/mlisp

lisp:=$(shell if test -x $(preferred_lisp); then \
		echo $(preferred_lisp); \
	     elif test -x $(alt_lisp0); then \
		echo $(alt_lisp0); \
	     elif test -x $(alt_lisp1); then \
		echo $(alt_lisp1); \
	     else \
		echo mlisp; \
	     fi)

ROOT ?= /
prefix ?= $(ROOT)/usr
libdir ?= $(prefix)/lib
bindir ?= $(prefix)/bin
sbindir ?= $(prefix)/sbin

version := $(shell grep 'allegro-maild-version' version.cl | sed -e 's,.*"v\([0-9.]*\)".*,\1,')

installer-package := maild-$(version)-installer.tar.gz

REDHAT73 := $(shell rpm -q redhat-release-7.3 >/dev/null && echo yes)
SUSE92 := $(shell rpm -q suse-release-9.2 >/dev/null && echo yes)

SRCFILES=Makefile \
	maild.init maild.init.suse9 maild.sysconfig \
	maild.pam maild.pam.suse maild.pam.rh73 \
	aliases.cl auth.cl blacklist.cl bounce.cl checkers.cl \
	config.cl deliver.cl deliver-smtp.cl dns.cl emailaddr.cl \
	greylist.cl headers.cl input.cl ipaddr.cl lex.cl load.cl \
	lock.cl log.cl maild.cl mailer.cl queue.cl queue-process.cl \
	recips.cl rep-server.cl rewrite.cl sasl.cl security.cl smtp.cl \
	smtp-server-checkers.cl smtp-server.cl utils.cl version.cl www.cl 

DOCFILES=ALIASES MAILERS.txt NOTES STATS greylist.sql greylist.sql.notes

GREYADMINSRCFILES=Makefile greyadmin.cl login.clp menu.clp super.clp

all: clean maild/maild
	(cd greyadmin; ACL=$(lisp) make)

maild/maild: *.cl
	rm -fr maild
	$(lisp) -W -batch -L load.cl -e "(build)" -kill

check-mail-virus/check-mail-virus: check-mail-virus.cl
	rm -fr check-mail-virus
	$(lisp) -batch -L check-mail-virus.cl -e '(build)' -kill

install: install-system install-maild install-greyadmin

install-stop: FORCE
	-/etc/init.d/maild stop

install-start: FORCE
	/etc/init.d/maild start

install-common:
	mkdir -p $(libdir) $(sbindir)

install-maild: maild/maild install-common
	rm -fr $(libdir)/maild.old
	-mv $(libdir)/maild $(libdir)/maild.old
	cp -r maild $(libdir)
	chmod +s $(libdir)/maild/maild
	rm -f $(sbindir)/maild
	ln -s $(libdir)/maild/maild $(sbindir)/maild

install-check-mail-virus: check-mail-virus/check-mail-virus install-common
	rm -fr $(libdir)/check-mail-virus
	cp -r check-mail-virus $(libdir)
	chown root $(libdir)/check-mail-virus/*
	ln -sf ../lib/check-mail-virus/check-mail-virus \
	       $(sbindir)/check-mail-virus

ifeq ($(SUSE92),yes)
pamsrc=maild.pam.suse
else
ifeq ($(REDHAT73),yes)
pamsrc=maild.pam.rh73
else
pamsrc=maild.pam
endif
endif

install-system: FORCE
ifeq ($(SUSE92),yes)
	cp maild.init.suse9 $(ROOT)/etc/init.d/maild
else
	cp maild.init $(ROOT)/etc/rc.d/init.d/maild
endif
	if [ ! -e $(ROOT)/etc/sysconfig/maild ]; then \
		cp maild.sysconfig $(ROOT)/etc/sysconfig/maild; \
	fi
	if [ ! -e $(ROOT)/etc/pam.d/smtp ]; then \
		cp $(pamsrc) $(ROOT)/etc/pam.d/smtp; \
	fi

install-greyadmin: FORCE
	(cd greyadmin; make install)

clean: FORCE
	rm -f *.fasl maild.tar.gz maild-*.tar.gz autoloads.out
	rm -fr maild check-mail-virus
	(cd greyadmin; make clean)

realclean: clean
	rm -fr RPMS BUILD SRPMS 
	rm -f *~

update: FORCE
	cvs -q update -dP

tarball: all
	tar zcf maild.tar.gz maild

dist: tarball
	tar zcf $(installer-package) \
		maild.tar.gz \
		maild.init \
		maild-installer 

src-tarball: FORCE
	rm -fr maild-$(version) maild-$(version).tar.gz
	mkdir maild-$(version)
	cp $(SRCFILES) $(DOCFILES) maild-$(version)
	mkdir maild-$(version)/greyadmin
	(cd greyadmin && cp $(GREYADMINSRCFILES) ../maild-$(version)/greyadmin)
	tar zcf maild-$(version).tar.gz maild-$(version)
	rm -fr maild-$(version)

%.spec: %.spec.in version.cl
	sed -e "s/__VERSION__/$(version)/" < $< > $@

rpm-setup: FORCE
	mkdir -p BUILD RPMS SRPMS

%-rpm: maild-%.spec src-tarball rpm-setup
	rpmbuild --define "_sourcedir $(CURDIR)" \
		--define "_topdir $(CURDIR)" \
		-ba $<

# This is the "normal" target (non-redhat 7.3, non-suse)
redhat-rpm: maild.spec src-tarball rpm-setup
	rpmbuild --sign --define "_sourcedir $(CURDIR)" \
		--define "_topdir $(CURDIR)" \
		--define "_builddir $(CURDIR)/BUILD" \
		--define "_rpmdir $(CURDIR)/RPMS" \
		--define "_srcrpmdir $(CURDIR)/SRPMS" \
		-ba maild.spec

REPOHOST=fs1
REPODIR=/storage1/franz/$(ARCH)

install-repo:
	ssh root@$(REPOHOST) "rm -f $(REPODIR)/maild-*"
	scp RPMS/$(ARCH)/maild-$(version)-*.rpm root@$(REPOHOST):$(REPODIR)
	ssh root@$(REPOHOST) "createrepo -q $(REPODIR)"

ifeq ($(SUSE92),yes)
rpm: suse-rpm

else
ifeq ($(REDHAT73),yes)
rpm: rh73-rpm

else
rpm: redhat-rpm

endif
endif

FORCE:
