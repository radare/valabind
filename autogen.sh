#!/bin/sh
[ -z "${EDITOR}" ] && EDITOR=vim
${EDITOR} configure.acr
# ${EDITOR} meson.build
acr -p
