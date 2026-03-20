VAPI=vstest.vapi
VALBINDCCFLAGS=-I. `pkg-config --cflags --libs gobject-2.0` -I/usr/include -L. -lvstest
VB=../../valabind

all:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	${CC} -fPIC -shared vstest.c -o libvstest.so `pkg-config --cflags --libs gobject-2.0`
	valabind-cc python vstest -NFood ${VAPI} ${VALBINDCCFLAGS} -x

cxx:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	valabind-cc python vstest -NFood -x ${VAPI} ${VALBINDCCFLAGS}
	valabind --cxx -m vstest vstest.vapi
	# compile vstest.cxx as included in test.cxx
	gcc -c vstest.c -I. `pkg-config gobject-2.0 --cflags --libs`
	g++ vstest.o test.cxx -I. `pkg-config gobject-2.0 --cflags --libs`
	#g++ test.cxx -I. `pkg-config gobject-2.0 --cflags --libs`

test:
	LD_LIBRARY_PATH=$${PWD} python3 test.py

foo:
	valabind-cc python vstest -NFood ${VAPI} -I. `pkg-config --cflags --libs gobject-2.0`

check-generated:
	$(VB) --ctypes --module=vstest -N Food vstest.vapi
	grep -q 'class Counter(IntEnum):' vstest.py
	grep -q 'START = 0' vstest.py
	$(VB) --ctypes --module=classes -N Test ../../t/go/classes.vapi
	grep -q 'class AA(Structure):' classes.py
	grep -q 'class BB(Structure):' classes.py
	grep -q 'class CC(Structure):' classes.py
	grep -q '__del__' classes.py
	$(VB) --ctypes --module=nsfn -N Test ../../t/go/namespace_function.vapi
	grep -q 'def fn1():' nsfn.py
	grep -q 'def fn6():' nsfn.py

clean:
	rm -f vstest.vapi vstest.h *.so vstest.cxx *.o *.i a.out vstest.c vstest.py* vstest_wrap.c* classes.py nsfn.py
