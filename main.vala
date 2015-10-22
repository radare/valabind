/* Copyright GPL3 - 2009-2013 -- pancake */

private static string[] files;
private static string vapidir;
private static string library;
private static bool show_version;
private static bool glibmode;
private static bool camelgetters;
private static bool cxxmode;
private static bool dlangoutput;
private static bool cxxoutput;
private static bool nodeoutput;
private static bool swigoutput;
private static bool ctypesoutput;
private static bool giroutput;
private static bool gooutput;
private static string modulename;
private static string? output;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] packages;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] include_dirs;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] namespaces;
[CCode (array_length = false, array_null_terminated = true)]
private static string[] defines;

private const OptionEntry[] options = {
	{ "define", 'D', 0, OptionArg.STRING_ARRAY,
	  ref defines, "define SYMBOL", "SYMBOL" },
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
	{ "camel-getters", 0, 0, OptionArg.NONE,
	  ref camelgetters, "translate {get,set}_foo into {get,set}Foo", null },
	{ "node-ffi", 0, 0, OptionArg.NONE,
	  ref nodeoutput, "generate node-ffi interface", null },
	{ "library", 'l', 0, OptionArg.STRING,
	  ref library, "library to link", null },
	{ "ctypes", 0, 0, OptionArg.NONE,
	  ref ctypesoutput, "generate python ctypes interface", null },
	{ "gir", 0, 0, OptionArg.NONE,
	  ref giroutput, "generate GIR (GObject-Introspection-Runtime)", null },
	{ "cxx", 0, 0, OptionArg.NONE,
	  ref cxxoutput, "generate C++ interface code", null },
	{ "dlang", 0, 0, OptionArg.NONE,
	  ref dlangoutput, "generate D bindings", null },
	{ "go", 0, 0, OptionArg.NONE,
	  ref gooutput, "generate Go bindings", null },
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
	if (swigoutput && count++ == 0) {
		writer = new SwigWriter (cxxmode);
		writer.add_define ("VALABIND_SWIG");
	}
	if (nodeoutput && count++ == 0) {
		writer = new NodeFFIWriter ();
		writer.add_define ("VALABIND_NODEJS");
	}
	if (ctypesoutput && count++ == 0) {
		writer = new CtypesWriter ();
		writer.add_define ("VALABIND_CTYPES");
	}
	if (giroutput && count++ == 0) {
		writer = new GirWriter ();
		writer.add_define ("VALABIND_GIR");
	}
	if (dlangoutput && count++ == 0) {
		writer = new DlangWriter ();
		writer.add_define ("VALABIND_DLANG");
	}
	if (cxxoutput && count++ == 0) {
		writer = new CxxWriter ();
		writer.add_define ("VALABIND_CXX");
	}
	if (gooutput && count++ == 0) {
		writer = new GoWriter ();
		writer.add_define ("VALABIND_GO");
	}
	if (count == 0)
		error ("No output mode specified. Try --help\n");
	else if (count > 1)
		error ("Cannot specify more than one output mode\n");
	writer.modulename = modulename;
	writer.library = (library != null)? library: modulename;
	writer.include_dirs = include_dirs;
	writer.namespaces = namespaces;
	writer.camelgetters = camelgetters;

	writer.init (vapidir, glibmode);
	if (packages != null)
		foreach (var pkg in packages)
			writer.add_external_package (pkg);

	if (defines != null) {
		foreach (string define in defines) {
			writer.add_define (define);
		}
	}

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
