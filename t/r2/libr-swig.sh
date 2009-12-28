#!/bin/sh
MOD=$1
if [ -z "${MOD}" ]; then
	echo "Usage: libr-swig.sh [r_foo]"
	exit 1
fi
if [ -z "${R2PATH}" ]; then
	echo "No R2PATH specified"
	exit 1
fi

valaswig-cc python ${MOD} -I${R2PATH}/libr/include ${R2PATH}/libr/vapi/${MOD}.vapi -l${MOD}
