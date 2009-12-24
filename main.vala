/* Copyleft 2k9 -- pancake // nopcode.org */

static string[] files;
static bool show_version;
static string modulename;
static string? output;

const string version_string = "valaswig 0.1 - pancake nopcode.org";

private const OptionEntry[] options = {
	{ "", 0, 0, OptionArg.FILENAME_ARRAY, ref files, "vala/vapi input files", "FILE FILE .." },
	{ "version", 'v', 0, OptionArg.NONE, ref show_version, "specify module name", null },
	{ "output", 'o', 0, OptionArg.STRING, ref output, "specify module name", null },
	{ "module-name", 'm', 0, OptionArg.STRING, ref modulename, "specify module name", null },
	{ null }
};

int main (string[] args) {
	output = null;
	files = { "" };

	try {
		var opt_context = new OptionContext ("- ValaSwig");
		opt_context.set_help_enabled (true);
		opt_context.add_main_entries (options, null);
		opt_context.parse (ref args);
	} catch (OptionError e) {
		stdout.printf ("%s\n", e.message);
		stdout.printf ("Run '%s --help' to see a full list of available command line options.", args[0]);
		return 1;
	}

	if (show_version) {
		print ("%s\n", version_string);
		return 0;
	}

	if (modulename == null) {
		stderr.printf ("No modulename specified\n");
		return 1;
	}

	if (files.length == 0) {
	//if (files == null) {
		stderr.printf ("No files given\n");
		return 1;
	}

	SwigCompiler sc = new SwigCompiler (modulename);
	foreach (var file in files) {
		//stderr.printf ("FILE = %s\n", file);
		sc.add_source_file (file);
	}
	sc.parse ();
	if (output == null)
		output = "%s.i".printf (modulename);
	sc.emit_swig (output);
//	sc.emit_vapi ("blah");

	return 0;
}
