PKG=gtk+-2.0
VB=../../valabind
PKGCFG=$(shell ../../getvv)
VALAPREFIX=$(shell pkg-config --variable=prefix ${PKGCFG})
VALAVER=$(shell echo ${PKGCFG}|sed -e s,lib,,)
VAPI=${VALAPREFIX}/share/${VALAVER}/vapi/${PKG}.vapi

all:
	${VB} --module-name=gtk+-2.0 --glib --gear --pkg cairo --pkg gdk-2.0 --pkg atk ${VAPI}
