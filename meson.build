project('valabind', 'c', 'vala',
  version: run_command(
    'grep', '^VERSION ', meson.current_source_dir() / 'configure.acr', check: true,
  ).stdout().strip().split(' ')[1])

sources = files(
  'src/ctypeswriter.vala',
  'src/cxxwriter.vala',
  'src/dlangwriter.vala',
  'src/vlangwriter.vala',
  'src/girwriter.vala',
  'src/gowriter.vala',
  'src/nodeffiwriter.vala',
  'src/swigwriter.vala',
  'src/utils.vala',
  'src/valabindwriter.vala',
  'src/main.vala',
)

cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')
libvala_version = run_command(valac.cmd_array()[0], '--api-version', check: true).stdout().strip()
libvala_dep = dependency('libvala-@0@'.format(libvala_version))

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')

libvala_pkglibdir = libvala_dep.get_variable(pkgconfig: 'pkglibdir')
libvala_vapidir = libvala_dep.get_variable(pkgconfig: 'vapidir', default_value: '')
libvala_share_vapidir = join_paths(
  libvala_dep.get_variable(pkgconfig: 'datadir'),
  'vala',
  'vapi',
)

vala_args = [
  '--pkg', 'posix',
  '--pkg', 'codegen',
  '--vapidir', meson.current_source_dir() / 'private',
]

foreach vapidir : [libvala_vapidir, libvala_share_vapidir]
  if vapidir != ''
    vala_args += ['--vapidir', vapidir]
  endif
endforeach

valaccodegen_dep = cc.find_library('valaccodegen', dirs: [libvala_pkglibdir])

config_data = configuration_data()
config_data.set_quoted('VERSION_STRING', meson.project_version())

config_vala = configure_file(
  input: 'src/config.vala.in',
  output: 'config.vala',
  configuration: config_data,
)

executable(
  'valabind',
  [config_vala] + sources,
  dependencies: [glib_dep, gobject_dep, libvala_dep, valaccodegen_dep],
  vala_args: vala_args,
  include_directories: include_directories('private'),
  install: true,
  install_rpath: libvala_pkglibdir,
)

install_data('valabind-cc', install_dir: get_option('bindir'))
install_man('valabind.1', 'valabind-cc.1')
