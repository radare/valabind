VB=../../valabind

all:
	${VB} --gir --module=Test Test.vapi

check: all
	grep -q '<enumeration name="Mode"' Test.gir
	grep -q 'allow-none="1"' Test.gir
	grep -q '<array' Test.gir
	if command -v g-ir-compiler >/dev/null 2>&1; then g-ir-compiler Test.gir -o /tmp/Test.typelib >/dev/null; fi
