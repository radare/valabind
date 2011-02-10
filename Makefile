# run make V= to get debug output
VERSION=0.4
CC?=gcc
DESTDIR?=
PREFIX?=/usr
VALAC?=valac
BIN=valaswig
FILES=main.vala valaswigcompiler.vala swigwriter.vala cxxwriter.vala
VALAPKG=$$(if ${VALAC} --version|grep 0.10>/dev/null; then echo vala-0.10; else echo libvala-0.12; fi)
OBJS=$(subst .vala,.o,${FILES})
CFILES=$(subst .vala,.c,${FILES})
V=@

all: valaswig

valaswig: $(OBJS)
	@echo LN $(BIN)
	$(V)$(CC) -o $(BIN) $(OBJS) `pkg-config --libs gobject-2.0 glib-2.0 $(VALAPKG)`

$(CFILES): $(FILES)
	@for a in $(FILES) ; do \
	   c=`echo $$a|sed -e s,.vala,.c,`; \
	   if [ $$a -nt $$c ]; then \
	     $(MAKE) mrproper; $(MAKE) c ; fi ; done

$(OBJS): $(CFILES)
	@echo CC $(CFILES)
	$(V)$(CC) -c `pkg-config --cflags gobject-2.0 glib-2.0 $(VALAPKG)` $(CFILES)

a:
	@echo VALAPKG=$(VALAPKG)
	@echo ${VALAC} -g --pkg posix --pkg ${VALAPKG} ${FILES} -o ${BIN}
	@${VALAC} -g --pkg posix --pkg ${VALAPKG} ${FILES} -o ${BIN}

c:
	@echo VALAC $(FILES)
	$(V)${VALAC} -C -g --pkg posix --pkg ${VALAPKG} ${FILES} -o ${BIN}

install:
	mkdir -p ${DESTDIR}${PREFIX}/bin
	mkdir -p ${DESTDIR}${PREFIX}/share/man/man1
	cp ${BIN}.1 ${DESTDIR}${PREFIX}/share/man/man1
	cp ${BIN}-cc.1 ${DESTDIR}${PREFIX}/share/man/man1
	cp ${BIN} ${DESTDIR}${PREFIX}/bin
	cp ${BIN}-cc ${DESTDIR}${PREFIX}/bin

dist:
	rm -rf valaswig-${VERSION}
	hg clone . valaswig-${VERSION}
	cd valaswig-${VERSION} && $(MAKE) c
	rm -rf valaswig-${VERSION}/.hg
	tar czvf valaswig-${VERSION}.tar.gz valaswig-${VERSION}

clean:
	rm -f valaswig *.o

mrproper: clean
	rm -f *.c

deinstall: uninstall

uninstall:
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}-cc

.PHONY: all clean dist install uninstall deinstall
