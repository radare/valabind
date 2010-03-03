/* Copyleft 2009-2010 -- pancake // nopcode.org */

using Vala;

public class SwigCompiler {
	public bool pkgmode;
	public string pkgname;
	string modulename;
	string vapidir;
	CodeContext context;
	string[] source_files;

	public SwigCompiler (string modulename, string vapidir) {
		context = new CodeContext ();
		CodeContext.push (context);
		this.modulename = modulename;
		this.vapidir = vapidir;
		source_files = null;
		add_package (context, "glib-2.0");
		add_package (context, "gobject-2.0");
	}

	public void parse () {
		var parser = new Parser ();
		parser.parse (context);
		init ();
	}

	public bool init () {
		/* analysis and checks */
		var resolver = new SymbolResolver ();
		resolver.resolve (context);

		/* warning about type_symbol stuff */
		var analyzer = new SemanticAnalyzer ();
		analyzer.analyze (context);

		/* the flow */
		var flow_analyzer = new FlowAnalyzer ();
		flow_analyzer.analyze (context);

		return (context.report.get_errors () == 0);
	}

	public bool add_source_file (string path) {
		foreach (var f in source_files) {
			if (path == f)
				return false;
		}

		bool ret = FileUtils.test (path, FileTest.IS_REGULAR);
		if (ret) {
			if (!pkgmode)
				context.add_source_file (new SourceFile (context, path, true));
			source_files += path;
		} else {
			/* check in path */
			if (!add_package (context, path))
				SwigCompiler.error ("Cannot find '%s'.\n".printf (path));
		}
		return ret;
	}

	public void emit_vapi (string? output, string file) {
		var swig_writer = new CodeWriter ();
		swig_writer.write_file (context, file);
	}

	public void emit_swig (string file, bool show_externs, bool glibmode, bool cxxmode, string? include) {
		var swig_writer = new SwigWriter (modulename);
		if (swig_writer != null) {
			/* TODO: why not just pass a SwigCompiler reference to it? */
			swig_writer.show_externs = show_externs;
			swig_writer.glib_mode = glibmode;
			swig_writer.cxx_mode = cxxmode;
			swig_writer.pkgmode = pkgmode;
			swig_writer.pkgname = pkgname;
			if (include != null)
				swig_writer.includefiles.append (include);
			swig_writer.files = source_files;
			swig_writer.write_file (context, file);
		} else warning ("cannot create swig writer");
	}

	/* Ripped from Vala Compiler */
	private bool add_package (CodeContext context, string pkg) {
		print ("Adding dependency package %s\n", pkg);

		// ignore multiple occurences of the same package
		if (context.has_package (pkg))
			return true;

		// TODO: Move the construction of this array somewhere else :)
		string[] vapi_directories = {
			vapidir//,
			//"/usr/share/vala/vapi" /* XXX harcoded path */
		};
	
		var package_path = context.get_package_path (pkg, vapi_directories);
		if (package_path == null) {
			stderr.printf ("Cannot find package path '%s'", pkg);
			return false;
		}

		// XXX find better way to do this
		//if (package_path[0] == '.') {
		if (pkgmode) {
			//print ("==> %s\n", package_path);
			add_source_file (package_path);
		}

		context.add_source_file (new SourceFile (context, package_path, true));
		context.add_package (pkg);
		
		var deps_filename = Path.build_filename (Path.get_dirname (package_path), "%s.deps".printf (pkg));
		if (FileUtils.test (deps_filename, FileTest.EXISTS)) {
			try {
				string deps_content;
				size_t deps_len;

				FileUtils.get_contents (deps_filename, out deps_content, out deps_len);
				foreach (string dep in deps_content.split ("\n")) {
					dep = dep.strip ();
					if (dep != "") {
						if (!add_package (context, dep))
							Report.error (null, "%s, dependency of %s, not found in specified Vala API directories".printf (dep, pkg));
					}
				}
			} catch (FileError e) {
				Report.error (null, "Unable to read dependency file: %s"
					.printf (e.message));
			}
		}
		return true;
	}

	public static void error (string msg) {
		stderr.printf ("\x1b[31mERROR:\x1b[0m %s\n", msg);
		Posix.exit (1);
	}

	public static void warning (string msg) {
		stderr.printf ("\x1b[33mWARNING:\x1b[0m %s\n", msg);
	}
}
