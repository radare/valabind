project('valabind', 'c', 'vala',
  version: run_command('./configure', '-qV').stdout().strip())

add_project_arguments([
  '--vapidir', join_paths(meson.current_source_dir(), 'vapi')], 
  language: 'vala')

files = [
  'config.vala',
  'ctypeswriter.vala',
  'cxxwriter.vala',
  'dlangwriter.vala',
  'vlangwriter.vala',
  'girwriter.vala',
  'gowriter.vala',
  'nodeffiwriter.vala',
  'swigwriter.vala',
  'utils.vala',
  'valabindwriter.vala',
  'main.vala',
]

cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')
libvala_version = run_command(valac.cmd_array()[0], '--api-version').stdout().strip()
libvala_dep = dependency('libvala-@0@'.format(libvala_version))

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')

valaccodegen_dep = cc.find_library('valaccodegen', dirs : [libvala_dep.get_pkgconfig_variable('pkglibdir')])

executable(
  'valabind',
  files,
  dependencies: [glib_dep, gobject_dep, libvala_dep, valaccodegen_dep],
  vala_args: ['--pkg', 'posix', '--includedir', '../private',
    '--vapidir', '../private', '--pkg', 'codegen'],
  include_directories: include_directories('../private'),
  install: true,
  install_rpath: libvala_dep.get_pkgconfig_variable('pkglibdir')
)

install_data('valabind-cc', install_dir: get_option('bindir'))
install_man('valabind.1', 'valabind-cc.1')
