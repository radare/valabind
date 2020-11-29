all:
	make -C ../..
	../../valabind -m system --vlang system.vapi
	rm -rf system
	mkdir -p system
	mv system.v system/lib.v
	v run main.v
