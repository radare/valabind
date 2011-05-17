# XXX: Hardcoded path
R2PATH=/home/pancake/prg/radare2/

all: perl ruby python csharp

perl:
	R2PATH=${R2PATH} sh libr-swig.sh perl r_bp

ruby:
	R2PATH=${R2PATH} sh libr-swig.sh ruby r_bp

python:
	rm -f r_bp.so
	R2PATH=${R2PATH} sh libr-swig.sh python r_bp

csharp:
	R2PATH=${R2PATH} sh libr-swig.sh csharp r_bp
	mcs -main:test *.cs

.PHONY: all perl ruby python csharp
