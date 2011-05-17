# run make V= to get debug output
VERSION=0.4.1
CONTACT=pancake@nopcode.org
CC?=gcc
DESTDIR?=
PREFIX?=/usr
VALAC?=valac
BIN=valabind
FILES=main.vala config.vala valabindcompiler.vala
FILES+=girwriter.vala swigwriter.vala cxxwriter.vala gearwriter.vala
RTLIBS=gobject-2.0 glib-2.0
VALAPKG=`./getvv`
#VALAPKG=libvala-0.14
OBJS=$(subst .vala,.o,${FILES})
CFILES=$(subst .vala,.c,${FILES})
V=@

all: config.vala ${BIN}

${BIN} : $(OBJS)
	@echo LN $(BIN)
	$(V)$(CC) -o $(BIN) $(OBJS) $$(pkg-config --libs ${RTLIBS} ${VALAPKG})

config.vala:
	@echo "mkconfig config.vala"
	@echo "const string version_string = \"${BIN} ${VERSION} - ${CONTACT}\";" > config.vala

$(CFILES): $(FILES)
	@for a in $(FILES) ; do \
	   c=`echo $$a|sed -e s,.vala,.c,`; \
	   if [ $$a -nt $$c ]; then \
	     $(MAKE) mrproper; $(MAKE) c || exit 1 ; fi ; done

$(OBJS): $(CFILES)
	@echo Using $(VALAPKG)
	@echo CC $(CFILES)
	$(V)$(CC) -c $$(pkg-config --cflags ${RTLIBS} ${VALAPKG}) $(CFILES)

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
	rm -rf valabind-${VERSION}
	hg clone . valabind-${VERSION}
	cd valabind-${VERSION} && $(MAKE) c
	rm -rf valabind-${VERSION}/.hg
	tar czvf valabind-${VERSION}.tar.gz valabind-${VERSION}

clean:
	rm -f valabind *.o config.vala

mrproper: clean
	rm -f *.c

deinstall: uninstall

uninstall:
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}-cc

.PHONY: all clean dist install uninstall deinstall mrproper c a
