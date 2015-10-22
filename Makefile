_VERSION=0.9.3
#GIT_TIP=$(shell [ -d .git ] && git log HEAD^..HEAD 2>/dev/null |head -n1|cut -d ' ' -f2)
GIT_TIP=$(shell git describe --tags)
CONTACT=pancake@nopcode.org
PWD:=$(shell pwd)
DESTDIR?=
PREFIX?=/usr
MANDIR?=$(PREFIX)/share/man
CC?=gcc
VALAFLAGS:=$(foreach w,$(CPPFLAGS) $(CFLAGS) $(LDFLAGS),-X $(w))
VALAC?=valac -g --cc="$(CC)" $(VALAFLAGS)
RTLIBS=gobject-2.0 glib-2.0
VALAPKG:=$(shell ./getvv)
BUILD?=build
BIN=valabind
SRC=config.vala main.vala valabindwriter.vala nodeffiwriter.vala utils.vala
SRC+=girwriter.vala swigwriter.vala cxxwriter.vala ctypeswriter.vala dlangwriter.vala gowriter.vala
VAPIS:=$(SRC:%.vala=$(BUILD)/%.vapi)
CSRC:=$(SRC:%.vala=$(BUILD)/%.c)
VALA_FILTER=$(filter %.vala,$?)
TEMPS=$(addprefix --use-fast-vapi=,$(filter-out $(VALA_FILTER:%.vala=$(BUILD)/%.vapi),$(VAPIS)))
TEMPS+=$(VALA_FILTER) $(patsubst %.vala,$(BUILD)/%.c,$(filter-out $?,$^))

ifneq ($(GIT_TIP),)
SGIT_TIP=$(shell echo ${GIT_TIP} | sed -e s,${_VERSION},,)
else
SGIT_TIP=$(GIT_TIP)
endif
ifneq ($(SGIT_TIP),)
VERSION=$(_VERSION)-$(SGIT_TIP)
else
VERSION=$(_VERSION)
endif

INSTALL_MAN?=install -m0644
INSTALL_PROGRAM?=install -m0755

ifneq ($(W32),)
VALAFLAGS+=-D W32=1
PREFIX=/opt/gtk3w32/
PKG_CONFIG_PATH=$(W32_PREFIX)/lib/pkgconfig
CFLAGS=-I$(PREFIX)/include/glib
CFLAGS+=-I$(PREFIX)/include/glib
LDFLAGS=-L$(PREFIX)/lib
CC=i686-pc-mingw32-gcc
all: $(BIN).exe
else
all: $(BIN)
endif

w32:
	$(MAKE) W32=1

.PRECIOUS: $(BUILD)/%.c $(BUILD)/%.vapi
$(BIN).exe: $(SRC) | $(VAPIS)
	@echo 'Compiling $(VALA_FILTER) -> $@'
	$(VALAC) --vapidir=. -D W32 -X "${CFLAGS}" -X "${LDFLAGS}" -o $@ --pkg $(VALAPKG) --save-temps ${TEMPS} windows.c --pkg windows
	@mv $(VALA_FILTER:%.vala=%.c) $(BUILD)

$(BIN): $(SRC) | $(VAPIS)
	@echo 'Compiling $(VALA_FILTER) -> $@'
	$(VALAC) -o $@ --pkg posix --pkg $(VALAPKG) --save-temps ${TEMPS}
	@mv $(VALA_FILTER:%.vala=%.c) $(BUILD)

$(BUILD)/%.vapi: %.vala | $(BUILD)
	@echo 'Generating $< -> $@'
	@$(VALAC) $(VALAFLAGS) --fast-vapi=$@ $<
	@${MAKE} config.vala

config.vala:
	@echo 'Generating $@'
	@echo 'const string version_string = "$(VERSION)";' > $@

$(BUILD):
	mkdir -p $@

install_dirs:
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(MANDIR)/man1

install: install_dirs
	$(INSTALL_MAN) $(BIN).1 $(DESTDIR)$(MANDIR)/man1
	$(INSTALL_MAN) $(BIN)-cc.1 $(DESTDIR)$(MANDIR)/man1
	$(INSTALL_PROGRAM) $(BIN) $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(BIN)-cc $(DESTDIR)$(PREFIX)/bin

symstall: install_dirs
	chmod +x $(PWD)/$(BIN)-cc
	ln -fs $(PWD)/$(BIN).1 $(DESTDIR)$(MANDIR)/man1
	ln -fs $(PWD)/$(BIN)-cc.1 $(DESTDIR)$(MANDIR)/man1
	ln -fs $(PWD)/$(BIN) $(DESTDIR)$(PREFIX)/bin
	ln -fs $(PWD)/$(BIN)-cc $(DESTDIR)$(PREFIX)/bin

dist:
	$(MAKE) shot GIT_TIP=

shot:
	rm -rf valabind-$(VERSION)
	git clone . valabind-$(VERSION)
	cd valabind-$(VERSION) && $(MAKE) config.vala
	rm -rf valabind-$(VERSION)/.git
	tar czvf valabind-$(VERSION).tar.gz valabind-$(VERSION)

mrproper clean:
	rm -f config.vala
	rm -rf $(BUILD) $(BIN)
	rm -rf $(CSRC)

deinstall: uninstall

uninstall:
	-rm $(DESTDIR)$(MANDIR)/man1/$(BIN).1
	-rm $(DESTDIR)$(MANDIR)/man1/$(BIN)-cc.1
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)-cc

.PHONY: all clean dist install symstall uninstall deinstall mrproper 
