# XXX: Hardcoded path
# HACK(eddyb): Relative path, more chance of success :)
R2PATH:=../../../radare2
MOD:=r_bp
NS:=Radare
FLAGS:=$(MOD) $(MOD) -N$(NS) -I$(R2PATH)/libr/include --vapidir=$(R2PATH)/r2-bindings/vapi -l$(MOD)

all: perl ruby python csharp

perl:
	valabind-cc perl $(FLAGS)

ruby:
	valabind-cc ruby $(FLAGS)

python:
	rm -f r_bp.so
	valabind-cc python $(FLAGS)

csharp:
	valabind-cc csharp $(FLAGS)
	mcs -main:test *.cs

.PHONY: all perl ruby python csharp
