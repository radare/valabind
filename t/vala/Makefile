VAPI=vstest.vapi
SWIGCFLAGS=-I. `pkg-config --cflags --libs gobject-2.0` -I/usr/include -g

all:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	${CC} -fPIC -shared vstest.c -o libvstest.so `pkg-config --cflags --libs gobject-2.0`
	LDFLAGS="-L. -lvstest" valabind-cc python vstest ${VAPI} ${SWIGCFLAGS} -x

cxx:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	LDFLAGS="-L. -lvstest" valabind-cc python vstest -X ${VAPI} ${SWIGCFLAGS}
	# compile vstest.cxx as included in test.cxx
	gcc -c vstest.c -I. `pkg-config gobject-2.0 --cflags --libs`
	g++ vstest.o test.cxx -I. `pkg-config gobject-2.0 --cflags --libs`
	#g++ test.cxx -I. `pkg-config gobject-2.0 --cflags --libs`

v8:
	../../valabind --gear -m vstest vstest.vapi

test:
	LD_LIBRARY_PATH=. python test.py

foo:
	valabind-cc python vstest ${VAPI} -I. `pkg-config --cflags --libs gobject-2.0`

clean:
	rm -f vstest.vapi vstest.h *.so vstest.cxx *.o *.i a.out vstest.c vstest.py* vstest_wrap.c
