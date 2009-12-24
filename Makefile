DESTDIR?=
PREFIX?=/usr
BIN=valaswig
FILES=main.vala swigcompiler.vala swigwriter.vala 

all:
	valac -g --pkg vala-1.0 ${FILES} -o ${BIN}

install:
	cp ${BIN} ${DESTDIR}${PREFIX}/bin
	cp ${BIN}-cc ${DESTDIR}${PREFIX}/bin

uninstall:
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}
	-rm ${DESTDIR}${PREFIX}/bin/${BIN}-cc

.PHONY: all install
