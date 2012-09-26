WGET=wget --no-check-certificate

all: jna.jar
	javac -cp jna.jar:. AsmExample.java RAsmCode.java RAsm.java
	java -cp jna.jar:. AsmExample

jna.jar:
	${WGET} https://raw.github.com/twall/jna/3.4.1/dist/jna.jar

clean:
	rm -f *.class

mrproper: clean
	rm -f jna.jar
