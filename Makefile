_VERSION=?
-include config.mk

PWD:=$(shell pwd)
SRCDIR?=src
#GIT_TIP=$(shell [ -d .git ] && git log HEAD^..HEAD 2>/dev/null |head -n1|cut -d ' ' -f2)
GIT_TIP=$(shell git describe --tags)
DESTDIR?=
PREFIX?=/usr
MANDIR?=$(PREFIX)/share/man
CC?=gcc
VALAFLAGS:=$(foreach w,$(CPPFLAGS) $(CFLAGS) $(LDFLAGS),-X $(w))
VALAC?=valac -g --cc="$(CC)" $(VALAFLAGS)
RTLIBS=gobject-2.0 glib-2.0
VALAPKG:=lib$(shell ./getvv)
BUILD?=build
BIN=valabind
GENERATED_SRC=$(BUILD)/config.vala
VALA_SRCS=main.vala valabindwriter.vala nodeffiwriter.vala utils.vala
VALA_SRCS+=girwriter.vala swigwriter.vala cxxwriter.vala ctypeswriter.vala dlangwriter.vala gowriter.vala
VALA_SRCS+=vlangwriter.vala
SRC:=$(GENERATED_SRC) $(addprefix $(SRCDIR)/,$(VALA_SRCS))
CSRC:=$(VALA_SRCS:%.vala=%.c)

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

VALA_VERSION=$(shell ./getvv)
VALA_PKGLIBDIR=$(shell pkg-config --variable=pkglibdir lib${VALA_VERSION})
VALA_VAPIDIR=$(shell pkg-config --variable=vapidir lib${VALA_VERSION})
VALA_SHARE_VAPIDIR=$(shell pkg-config --variable=datadir lib${VALA_VERSION})/vala/vapi
ifeq ($(VALA_PKGLIBDIR),)
VALA_LIBDIR=$(shell pkg-config --variable=libdir lib${VALA_VERSION})
VALA_PKGLIBDIR=$(VALA_LIBDIR)/$(shell ./getvv)
endif
VALA_PRIVATE_CODEGEN=--pkg $(VALAPKG)
VALA_PRIVATE_CODEGEN+=--vapidir=$(PWD)/private --pkg codegen -X -I$(PWD)/private
ifneq ($(VALA_VAPIDIR),)
VALA_PRIVATE_CODEGEN+=--vapidir=$(VALA_VAPIDIR)
endif
ifneq ($(wildcard $(VALA_SHARE_VAPIDIR)),)
VALA_PRIVATE_CODEGEN+=--vapidir=$(VALA_SHARE_VAPIDIR)
endif
ifneq ($(R2PM_PREFIX),)
VALA_PRIVATE_CODEGEN+=--vapidir=${R2PM_PREFIX}/share/vala/vapi/
endif
VALA_PRIVATE_CODEGEN+=-X -L$(VALA_PKGLIBDIR) -X -lvalaccodegen
ifneq ($(shell uname),Darwin)
VALA_PRIVATE_CODEGEN+=-X -Wl,-rpath=$(VALA_PKGLIBDIR)
endif

w32:
	$(MAKE) W32=1

$(BIN).exe: $(SRC) $(SRCDIR)/windows.c $(SRCDIR)/windows.vapi
	@echo 'Compiling $@'
	$(VALAC) --vapidir=$(SRCDIR) -D W32 -X "${CFLAGS}" -X "${LDFLAGS}" -o $@ --pkg $(VALAPKG) $(SRC) $(SRCDIR)/windows.c --pkg windows

$(BIN): $(SRC)
	@echo 'Compiling $@'
	$(VALAC) -o $@ --pkg posix $(VALA_PRIVATE_CODEGEN) $(SRC)

$(GENERATED_SRC): Makefile | $(BUILD)
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
	rm -rf valabind-$(VERSION)/.git
	tar czvf valabind-$(VERSION).tar.gz valabind-$(VERSION)

mrproper clean:
	rm -rf $(BUILD) $(BIN) $(BIN).exe
	rm -rf $(CSRC)

deinstall: uninstall

uninstall:
	-rm $(DESTDIR)$(MANDIR)/man1/$(BIN).1
	-rm $(DESTDIR)$(MANDIR)/man1/$(BIN)-cc.1
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)
	-rm $(DESTDIR)$(PREFIX)/bin/$(BIN)-cc

.PHONY: all clean dist install symstall uninstall deinstall mrproper 
