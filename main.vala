/* Copyleft 2009-2011 -- pancake // nopcode.org */

static string[] files;
static string includefile;
static string vapidir;
static bool show_version;
static bool show_externs;
static bool glibmode;
static bool cxxmode;
static bool cxxoutput;
static bool gearoutput;
static bool swigoutput;
static bool giroutput;
static string modulename;
static string? output;
static string? useprofile;
[CCode (array_length = false, array_null_terminated = true)]
static string[] packages;

private const OptionEntry[] options = {
	{ "pkg", 0, 0, OptionArg.STRING_ARRAY,
	  ref packages, "Include binding for PACKAGE", "PACKAGE..." },
	{ "vapidir", 'V', 0, OptionArg.STRING,
	  ref vapidir, "define alternative vapi directory", null },
	{ "include", 'i', 0, OptionArg.STRING,
	  ref includefile, "include file", null },
	{ "externs", 'e', 0, OptionArg.NONE,
	  ref show_externs, "render externs", null },
	{ "version", 'v', 0, OptionArg.NONE,
	  ref show_version, "show version information", null },
	{ "output", 'o', 0, OptionArg.STRING,
	  ref output, "specify output file name", null },
	{ "module", 'm', 0, OptionArg.STRING,
	  ref modulename, "specify module name", "NAME" },
	{ "profile", 'p', 0, OptionArg.NONE,
	  ref useprofile, "select Vala profile (posix, gobject, dova)", "posix" },
	{ "glib", 'g', 0, OptionArg.NONE,
	  ref glibmode, "work in glib/gobject mode", null },
	{ "cxx-swig", 'x', 0, OptionArg.NONE,
	  ref cxxmode, "generate c++ code for SWIG", null },
	{ "swig", '\0', 0, OptionArg.NONE,
	  ref swigoutput, "generate swig interface code (default)", null },
	{ "gear", '\0', 0, OptionArg.NONE,
	  ref gearoutput, "generate gearbox interface code", null },
	{ "gir", '\0', 0, OptionArg.NONE,
	  ref giroutput, "generate GIR (GObject-Introspection-Runtime)", null },
	{ "cxx", '\0', 0, OptionArg.NONE,
	  ref cxxoutput, "output C++ code instead of SWIG interface", null },
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

	if (modulename == null) {
		stderr.printf ("No modulename specified. Use --module or --help\n");
		return 1;
	}

	if (files.length == 0) {
		stderr.printf ("No files given\n");
		return 1;
	}

	int count = 0;
	if (swigoutput) count++;
	if (gearoutput) count++;
	if (giroutput) count++;
	if (cxxoutput) count++;
	if (count>1) {
		stderr.printf ("Cannot use --swig, --gir, --gear or --cxx together\n");
		return 1;
	}

	string profile = (useprofile!=null)? useprofile: "posix";
	if (glibmode) profile = "gobject";
	// TODO: dova?

	var vbc = new ValabindCompiler (modulename, vapidir, profile);
	if (packages != null)
		foreach (var pkg in packages) {
			print ("Adding dependency "+pkg+"\n");
			vbc.add_external_package (pkg);
		}

	// TODO: passing more than one source doesnt seems to work :/
	foreach (var file in files) {
		if (file.index_of (".vapi") == -1) {
			vbc.pkgmode = true;
			vbc.pkgname = file;
		}
		vbc.add_source_file (file);
	}
	vbc.parse ();
	if (output == null)
		output = "%s.%s".printf (modulename,
			giroutput?"gir":
			gearoutput?"gear":
			cxxoutput?"cxx": "i");
	if (gearoutput) vbc.emit_gear (output, show_externs, glibmode, cxxmode, includefile);
	else if (giroutput) vbc.emit_gir (output, show_externs, glibmode, cxxmode, includefile);
	else if (cxxoutput) vbc.emit_cxx (output, show_externs, glibmode, cxxmode, includefile);
	else vbc.emit_swig (output, show_externs, glibmode, true, includefile);
	return 0;
}
