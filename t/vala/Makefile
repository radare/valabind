VAPI=vstest.vapi
SWIGCFLAGS=-I. `pkg-config --cflags --libs gobject-2.0` -I/usr/include -g

all:
	valac -H vstest.h -C --vapi=${VAPI} --library=libvstest vstest.vala
	${CC} -fPIC -shared vstest.c -o libvstest.so `pkg-config --cflags --libs gobject-2.0`
	LDFLAGS="-L. -lvstest" valaswig-cc python vstest ${VAPI} ${SWIGCFLAGS}

test:
	LD_LIBRARY_PATH=. python test.py

foo:
	valaswig-cc python vstest ${VAPI} -I. `pkg-config --cflags --libs gobject-2.0`

clean:
	rm -f vstest.vapi vstest.h *.so
