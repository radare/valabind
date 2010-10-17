#!/bin/sh
LANG=$1
MOD=$2
if [ -z "${MOD}" ]; then
	echo "Usage: libr-swig.sh [python|perl|ruby] [r_foo]"
	exit 1
fi
if [ -z "${R2PATH}" ]; then
	echo "No R2PATH specified"
	exit 1
fi

valaswig-cc ${LANG} ${MOD} -I${R2PATH}/libr/include ${R2PATH}/swig/vapi/${MOD}.vapi -l${MOD}
