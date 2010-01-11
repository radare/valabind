/* Copyleft 2009-2010 -- pancake // nopcode.org */

static string[] files;
static string includefile;
static bool show_version;
static bool show_externs;
static bool glibmode;
static string modulename;
static string? output;

const string version_string = "valaswig 0.1 - pancake @ nopcode.org";

private const OptionEntry[] options = {
	{ "", 0, 0, OptionArg.FILENAME_ARRAY,
	  ref files, "vala/vapi input files", "FILE FILE .." },
	{ "include", 'i', 0, OptionArg.STRING,
	  ref includefile, "include file", null },
	{ "externs", 'e', 0, OptionArg.NONE,
	  ref show_externs, "render externs", null },
	{ "version", 'v', 0, OptionArg.NONE,
	  ref show_version, "show version information", null },
	{ "output", 'o', 0, OptionArg.STRING,
	  ref output, "specify output file name", null },
	{ "module-name", 'm', 0, OptionArg.STRING,
	  ref modulename, "specify module name", null },
	{ "glib", 'g', 0, OptionArg.NONE,
	  ref glibmode, "work in glib/gobject mode", null },
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
		stdout.printf ("%s\nTry --help.\n", e.message);
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
		stderr.printf ("No files given\n");
		return 1;
	}

	SwigCompiler sc = new SwigCompiler (modulename);
	foreach (var file in files) {
		sc.add_source_file (file);
	}
	sc.parse ();
	if (output == null)
		output = "%s.i".printf (modulename);
	sc.emit_swig (output, show_externs, glibmode, includefile);

	return 0;
}
