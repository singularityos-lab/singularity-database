project('singularity-database', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-database"', language: 'c')
add_project_arguments('-w', language: 'c')
add_project_arguments(['--vapidir=' + meson.current_source_dir() / 'vapi'], language: 'vala')
subdir('po')

cc          = meson.get_compiler('c')
gee_dep     = dependency('gee-0.8')
gio_dep     = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
json_dep    = dependency('json-glib-1.0')
sqlite_dep  = dependency('sqlite3')
xml_dep     = dependency('libxml-2.0')
zlib_dep    = dependency('zlib')
secret_dep  = dependency('libsecret-1')
cairo_dep   = dependency('cairo')
pango_dep   = dependency('pangocairo')
pixbuf_dep  = dependency('gdk-pixbuf-2.0')
math_dep    = cc.find_library('m')
nettle_dep  = dependency('nettle')

core_deps = [gee_dep, gio_dep, gio_unix_dep, json_dep, sqlite_dep, xml_dep, zlib_dep, math_dep, nettle_dep]

model = files(
  'src/model/value.vala',
  'src/model/sql.vala',
  'src/model/format.vala',
  'src/model/schema.vala',
  'src/model/meta.vala',
  'src/model/database.vala',
  'src/model/query.vala',
  'src/model/recordset.vala',
  'src/model/objects.vala',
  'src/model/templates.vala',
  'src/model/crypt.vala',
  'src/model/crypt_vfs.c',
  'src/model/locks.vala',
  'src/model/repair.vala',
  'src/model/access_sql.vala',
  'src/model/sql_access.vala',
  'src/model/query_engine.vala',
  'src/model/input_mask.vala',
  'src/model/links.vala',
  'src/model/analysis.vala',
  'src/script/value.vala',
  'src/script/lexer.vala',
  'src/script/ast.vala',
  'src/script/parser.vala',
  'src/script/interp.vala',
  'src/script/format.vala',
  'src/script/builtins.vala',
  'src/script/objects.vala',
  'src/script/dao.vala',
  'src/script/macros.vala',
)

io = files(
  'src/io/zip.vala',
  'src/io/csv.vala',
  'src/io/xlsx.vala',
  'src/io/json_io.vala',
  'src/io/sql_dump.vala',
  'src/io/mdb.vala',
  'src/io/access_text.vala',
  'src/io/transfer.vala',
  'src/io/report_export.vala',
  'src/io/data_export.vala',
  'src/io/access_import.vala',
  'src/io/office_crypt.vala',
  'src/io/office_aes.c',
)

remote = files(
  'src/remote/engine.vala',
  'src/remote/pg.vala',
  'src/remote/mysql.vala',
  'src/remote/sqlite_engine.vala',
  'src/remote/client.vala',
  'src/remote/server_links.vala',
)

report_engine = files(
  'src/model/report.vala',
  'src/model/chart.vala',
  'src/model/report_banded.vala',
)

server_test_deps = []

tests = {
  'schema': 'tests/schema_test.vala',
  'query': 'tests/query_test.vala',
  'io': 'tests/io_test.vala',
  'report': 'tests/report_test.vala',
  'mdb': 'tests/mdb_test.vala',
  'pg': 'tests/pg_test.vala',
  'mysql': 'tests/mysql_test.vala',
  'client': 'tests/client_test.vala',
  'accesstext': 'tests/accesstext_test.vala',
  'crypt': 'tests/crypt_test.vala',
  'script': 'tests/script_test.vala',
}

foreach name, src : tests
  t = executable('database-' + name + '-test',
    model + io + remote + report_engine + files(src),
    dependencies: core_deps + [cairo_dep, pango_dep, pixbuf_dep],
    vala_args: ['--pkg', 'zlib'],
  )
  test(name, t, timeout: 120)
  server_test_deps += t
endforeach

test('servers', find_program('tests/run-server-tests.sh'),
  args: [meson.current_build_dir()],
  depends: server_test_deps,
  timeout: 1500,
  suite: 'servers',
  is_parallel: false,
)

gtk_dep = dependency('gtk4')
gtksource_dep = dependency('gtksourceview-5')
libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

gnome = import('gnome')
resources = gnome.compile_resources(
  'singularity-database-resources',
  'resources/dev.sinty.database.gresource.xml',
  source_dir: meson.current_source_dir() / 'data' / 'icons',
)

ui = files(
  'src/ui/app.vala',
  'src/ui/widgets.vala',
  'src/ui/window.vala',
  'src/ui/welcome.vala',
  'src/ui/datasheet.vala',
  'src/ui/table_page.vala',
  'src/ui/designer.vala',
  'src/ui/relationships.vala',
  'src/ui/query_page.vala',
  'src/ui/sql_editor.vala',
  'src/ui/form_page.vala',
  'src/ui/report_page.vala',
  'src/ui/boards.vala',
  'src/ui/dialogs.vala',
  'src/ui/transfer_dialogs.vala',
  'src/ui/search_provider.vala',
  'src/ui/secrets.vala',
  'src/ui/result_grid.vala',
  'src/ui/connection_dialog.vala',
  'src/ui/client_window.vala',
  'src/ui/client_tabs.vala',
  'src/ui/client_dialogs.vala',
  'src/ui/automation.vala',
  'src/ui/automation_pages.vala',
  'src/ui/form_view.vala',
  'src/ui/form_designer.vala',
  'src/ui/report_designer.vala',
  'src/ui/tools_dialogs.vala',
)

executable('singularity-database',
  model + io + remote + report_engine + ui + [resources],
  dependencies: core_deps + [gtk_dep, gtksource_dep, cairo_dep, pango_dep, pixbuf_dep, libsingularity_dep, secret_dep],
  vala_args: ['--pkg', 'zlib'],
  install: true
)

install_data('data/dev.sinty.database.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.database.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.database.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.database.mime.xml',
  rename: 'dev.sinty.database.xml',
  install_dir: get_option('datadir') / 'mime' / 'packages'
)
install_data('data/dev.sinty.database.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
install_data('data/dev.sinty.database.search-provider.ini',
  rename: 'dev.sinty.database.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)
configure_file(
  input: 'data/dev.sinty.database.service.in',
  output: 'dev.sinty.database.service',
  configuration: {'bindir': get_option('prefix') / get_option('bindir')},
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)
install_data('data/icons/dev.sinty.database.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
