_VERSION=0.7.3git
#GIT_TIP=$(shell [ -d .git ] && git log HEAD^..HEAD 2>/dev/null |head -n1|cut -d ' ' -f2)
GIT_TIP=$(shell git describe --tags)
CONTACT=pancake@nopcode.org
PWD:=$(shell pwd)
DESTDIR?=
PREFIX?=/usr
MANDIR?=$(PREFIX)/share/man
CC?=gcc
VALAC?=valac -g --cc="$(CC)"
RTLIBS=gobject-2.0 glib-2.0
VALAPKG:=$(shell ./getvv)
BUILD?=build
BIN=valabind
SRC=config.vala main.vala valabindwriter.vala nodeffiwriter.vala utils.vala
SRC+=girwriter.vala swigwriter.vala cxxwriter.vala ctypeswriter.vala dlangwriter.vala
VAPIS:=$(SRC:%.vala=$(BUILD)/%.vapi)
CSRC:=$(SRC:%.vala=$(BUILD)/%.c)
VALA_FILTER=$(filter %.vala,$?)
TEMPS=$(addprefix --use-fast-vapi=,$(filter-out $(VALA_FILTER:%.vala=$(BUILD)/%.vapi),$(VAPIS)))
TEMPS+=$(VALA_FILTER) $(patsubst %.vala,$(BUILD)/%.c,$(filter-out $?,$^))

ifneq ($(GIT_TIP),)
VERSION=$(_VERSION)-$(GIT_TIP)
else
VERSION=$(_VERSION)
endif

all: $(BIN)

.PRECIOUS: $(BUILD)/%.c $(BUILD)/%.vapi

$(BIN): $(SRC) | $(VAPIS)
	@echo 'Compiling $(VALA_FILTER) -> $@'
	@$(VALAC) -o $@ --pkg posix --pkg $(VALAPKG) --save-temps ${TEMPS}
	@mv $(VALA_FILTER:%.vala=%.c) $(BUILD)

$(BUILD)/%.vapi: %.vala | $(BUILD)
	@echo 'Generating $< -> $@'
	@$(VALAC) --fast-vapi=$@ $<

config.vala:
	@echo 'Generating $@'
	@echo 'const string version_string = "$(VERSION)";' > $@

$(BUILD):
	mkdir -p $@

install_dirs:
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(MANDIR)/man1

install: install_dirs
	cp $(BIN).1 $(DESTDIR)$(MANDIR)/man1
	cp $(BIN)-cc.1 $(DESTDIR)$(MANDIR)/man1
	cp $(BIN) $(DESTDIR)$(PREFIX)/bin
	cp $(BIN)-cc $(DESTDIR)$(PREFIX)/bin

symstall: install_dirs
	chmod +x $(PWD)/$(BIN)-cc
	ln -fs $(PWD)/$(BIN).1 $(DESTDIR)$(MANDIR)/man1
	ln -fs $(PWD)/$(BIN)-cc.1 $(DESTDIR)$(MANDIR)/man1
	ln -fs $(PWD)/$(BIN) $(DESTDIR)$(PREFIX)/bin
	ln -fs $(PWD)/$(BIN)-cc $(DESTDIR)$(PREFIX)/bin

dist:
	rm -rf valabind-$(VERSION)
	git clone . valabind-$(VERSION)
	cd valabind-$(VERSION) && $(MAKE) config.vala #c
	rm -rf valabind-$(VERSION)/.git
	tar czvf valabind-$(VERSION).tar.gz valabind-$(VERSION)

mrproper clean:
	rm -f config.vala
	rm -rf $(BUILD) $(BIN)

deinstall: uninstall

uninstall:
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)-cc

.PHONY: all clean dist install symstall uninstall deinstall mrproper
