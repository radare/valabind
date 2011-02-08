VERSION=0.3
DESTDIR?=
PREFIX?=/usr
VALAC?=valac
BIN=valaswig
FILES=main.vala swigcompiler.vala swigwriter.vala cxxwriter.vala
VALAPKG=`if ${VALAC} --version|grep 0.10>/dev/null; then echo vala-0.10; else echo libvala-0.12; fi`

all:
	@echo VALAPKG=$(VALAPKG)
	@echo ${VALAC} -g --pkg posix --pkg ${VALAPKG} ${FILES} -o ${BIN}
	@${VALAC} -g --pkg posix --pkg ${VALAPKG} ${FILES} -o ${BIN}

c:
	${VALAC} -C -g --pkg posix --pkg ${VALAPKG} ${FILES} -o ${BIN}

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
	rm -rf valaswig-${VERSION}/.hg
	tar czvf valaswig-${VERSION}.tar.gz valaswig-${VERSION}

clean:
	rm -f valaswig

deinstall: uninstall

uninstall:
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}-cc

.PHONY: all clean dist install uninstall deinstall
