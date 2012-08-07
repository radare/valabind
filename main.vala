/* Copyleft 2009-2012 -- pancake // nopcode.org */

private static string[] files;
private static string vapidir;
private static bool show_version;
private static bool glibmode;
private static bool cxxmode;
private static bool cxxoutput;
private static bool nodeoutput;
private static bool swigoutput;
private static bool giroutput;
private static string modulename;
private static string? output;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] packages;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] include_dirs;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] namespaces;

/* helpers */
public void notice (string msg) {
	stderr.printf ("\x1b[34;1mNOTICE\x1b[0m %s\n", msg);
}

public void warning (string msg) {
	stderr.printf ("\x1b[33;1mWARNING\x1b[0m %s\n", msg);
}

public void error (string msg) {
	stderr.printf ("\x1b[31;1mERROR\x1b[0m %s\n", msg);
	Posix.exit (1);
}

private const OptionEntry[] options = {
	{ "pkg", 0, 0, OptionArg.STRING_ARRAY,
	  ref packages, "include binding for PACKAGE", "PACKAGE..." },
	{ "vapidir", 'V', 0, OptionArg.STRING,
	  ref vapidir, "define alternative vapi directory", "VAPIDIR" },
	{ "include-dir", 'I', 0, OptionArg.STRING_ARRAY,
	  ref include_dirs, "add include path", "INCLUDEDIR" },
	{ "version", 'v', 0, OptionArg.NONE,
	  ref show_version, "show version information", null },
	{ "output", 'o', 0, OptionArg.STRING,
	  ref output, "specify output file name", "OUTPUT" },
	{ "module", 'm', 0, OptionArg.STRING,
	  ref modulename, "specify module name", "NAME" },
	{ "namespace", 'N', 0, OptionArg.STRING_ARRAY,
	  ref namespaces, "include namespace in the output", "NSPACE" },
	{ "cxx-swig", 'x', 0, OptionArg.NONE,
	  ref cxxmode, "generate C++ code for SWIG", null },
	{ "glib", 0, 0, OptionArg.NONE,
	  ref glibmode, "call g_type_init before any constructor", null },
	{ "swig", 0, 0, OptionArg.NONE,
	  ref swigoutput, "generate swig interface code", null },
	{ "node-ffi", 0, 0, OptionArg.NONE,
	  ref nodeoutput, "generate node-ffi interface code", null },
	{ "gir", 0, 0, OptionArg.NONE,
	  ref giroutput, "generate GIR (GObject-Introspection-Runtime)", null },
	{ "cxx", 0, 0, OptionArg.NONE,
	  ref cxxoutput, "generate C++ interface code", null },
	{ "", 0, 0, OptionArg.FILENAME_ARRAY,
	  ref files, "vala/vapi input files", "FILE FILE .." },
	{ null }
};

int main (string[] args) {
	output = null;
	vapidir = ".";
	files = { "" };

	try {
		var opt_context = new OptionContext ("- valabind");
		opt_context.set_help_enabled (true);
		opt_context.add_main_entries (options, null);
		opt_context.parse (ref args);
	} catch (OptionError e) {
		stderr.printf ("%s\nTry --help\n", e.message);
		return 1;
	}

	if (show_version) {
		print ("%s\n", version_string);
		return 0;
	}

	if (modulename == null)
		error ("No modulename specified. Use --module or --help");

	if (files.length == 0)
		error ("No files given");

	ValabindWriter writer = null;
	int count = 0;
	if (swigoutput && count++ == 0)
		writer = new SwigWriter (cxxmode);
	if (nodeoutput && count++ == 0)
		writer = new NodeFFIWriter ();
	if (giroutput && count++ == 0)
		writer = new GirWriter ();
	if (cxxoutput && count++ == 0)
		writer = new CxxWriter ();
	if (count == 0)
		error ("No output mode specified. Try --help\n");
	else if (count > 1)
		error ("Cannot specify more than one output mode\n");

	writer.modulename = modulename;
	writer.include_dirs = include_dirs;
	writer.namespaces = namespaces;

	writer.init (vapidir, glibmode);
	if (packages != null)
		foreach (var pkg in packages)
			writer.add_external_package (pkg);

	// TODO: passing more than one source doesnt seems to work :/
	foreach (var file in files) {
		if (file.index_of (".vapi") == -1) {
			writer.pkgmode = true;
			writer.pkgname = file;
		}
		writer.add_source_file (file);
	}
	writer.parse ();
	if (output == null)
		output = writer.get_filename (modulename);
	writer.write (output);
	return 0;
}
