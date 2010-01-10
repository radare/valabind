R2PATH=/home/pancake/prg/radare2

all: perl ruby python csharp

perl:
	R2PATH=${R2PATH} sh libr-swig.sh perl r_bp

ruby:
	R2PATH=${R2PATH} sh libr-swig.sh ruby r_bp

python:
	R2PATH=${R2PATH} sh libr-swig.sh python r_bp

csharp:
	mcs -main:test *.cs
