VERSION=0.7.0
CONTACT=pancake@nopcode.org
PWD:=$(shell pwd)
DESTDIR?=
PREFIX?=/usr
MANDIR?=$(PREFIX)/share/man
VALAC?=valac -g
RTLIBS=gobject-2.0 glib-2.0
VALAPKG:=$(shell ./getvv)
CC?=gcc
CFLAGS?=-g
CFLAGS+=$(shell pkg-config --cflags $(RTLIBS) $(VALAPKG))
LNFLAGS?=
LNFLAGS+=$(shell pkg-config --libs $(RTLIBS) $(VALAPKG))
BUILD?=build
BIN=valabind
FILES=config.vala main.vala valabindwriter.vala nodeffiwriter.vala girwriter.vala swigwriter.vala cxxwriter.vala
VAPIS:=$(patsubst %.vala,$(BUILD)/%.vapi,$(FILES))
CFILES:=$(patsubst %.vala,$(BUILD)/%.c,$(FILES))
OBJS:=$(patsubst %.vala,$(BUILD)/%.o,$(FILES))

all: $(BIN)

$(BIN): $(OBJS)
	@echo 'Linking $^ -> $@'
	@$(CC) -o $@ $(LNFLAGS) $^

config.vala:
	@echo 'Generating $@'
	@echo 'const string version_string = "$(VERSION)";' > $@

%.o: %.c
	@echo 'Compiling $^ -> $@'
	@$(CC) -c -o $@ $(CFLAGS) $^

.PRECIOUS: $(BUILD)/%.c $(BUILD)/%.vapi
$(BUILD)/%.c: %.vala $(VAPIS)
	@echo 'Compiling $< -> $@'
	@$(VALAC) -C --pkg posix --pkg $(VALAPKG) $(addprefix --use-fast-vapi=,$(subst $(patsubst %.vala,$(BUILD)/%.vapi,$<),,$(VAPIS))) $<
	@mv $(patsubst $(BUILD)/%.c,%.c,$@) $@

$(BUILD)/%.vapi: %.vala | $(BUILD)
	@echo 'Generating $< -> $@'
	@$(VALAC) --fast-vapi=$@ $<

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
	hg clone . valabind-$(VERSION)
	cd valabind-$(VERSION) && $(MAKE) config.vala #c
	rm -rf valabind-$(VERSION)/.hg
	tar czvf valabind-$(VERSION).tar.gz valabind-$(VERSION)

clean:
	rm -rf $(BUILD) $(BIN)

mrproper: clean
	rm -f config.vala

deinstall: uninstall

uninstall:
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)-cc

.PHONY: all clean dist install symstall uninstall deinstall mrproper
