VAPI=vstest.vapi
VALBINDCCFLAGS=-I. `pkg-config --cflags --libs gobject-2.0` -I/usr/include -L. -lvstest

all:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	${CC} -fPIC -shared vstest.c -o libvstest.so `pkg-config --cflags --libs gobject-2.0`
	valabind-cc python vstest -NFood ${VAPI} ${VALBINDCCFLAGS} -x

cxx:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	valabind-cc python vstest -NFood -X ${VAPI} ${VALBINDCCFLAGS}
	# compile vstest.cxx as included in test.cxx
	gcc -c vstest.c -I. `pkg-config gobject-2.0 --cflags --libs`
	g++ vstest.o test.cxx -I. `pkg-config gobject-2.0 --cflags --libs`
	#g++ test.cxx -I. `pkg-config gobject-2.0 --cflags --libs`

test:
	python test.py

foo:
	valabind-cc python vstest -NFood ${VAPI} -I. `pkg-config --cflags --libs gobject-2.0`

clean:
	rm -f vstest.vapi vstest.h *.so vstest.cxx *.o *.i a.out vstest.c vstest.py* vstest_wrap.c*
