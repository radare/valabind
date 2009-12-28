/* Copyleft 2k9 -- pancake // nopcode.org */

using Vala;

public class SwigCompiler {
	string modulename;
	CodeContext context;
	string[] source_files;

	public SwigCompiler (string modulename) {
		context = new CodeContext ();
		CodeContext.push (context);
		this.modulename = modulename;
		source_files = null;
	}

	public void parse () {
		add_package (context, "glib-2.0");
		add_package (context, "gobject-2.0");
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

		if (context.report.get_errors () > 0)
			return false;
		return true;
	}

	public bool add_source_file (string path) {
		var source = new SourceFile (context, path, true);
		context.add_source_file (source);
		source_files += path;
		return true;
	}

	public void emit_vapi (string? output, string file) {
		var swig_writer = new CodeWriter ();
		swig_writer.write_file (context, file);
	}

	public void emit_swig (string file, bool show_externs, bool glibmode, string? include) {
		var swig_writer = new SwigWriter (modulename);
		if (swig_writer != null) {
			swig_writer.show_externs = show_externs;
			swig_writer.glib_mode = glibmode;
			if (include != null)
				swig_writer.includefiles.append (include);
			swig_writer.files = source_files;
			swig_writer.write_file (context, file);
		} else warning ("cannot create swig writer");
	}

	/* Ripped from Vala Compiler */
	private bool add_package (CodeContext context, string pkg) {
		/* XXX harcoded path */
		string[] vapi_directories = { "/usr/share/vala/vapi" };
		if (context.has_package (pkg)) {
			// ignore multiple occurences of the same package
			return true;
		}
	
		var package_path = context.get_package_path (pkg, vapi_directories);
		
		if (package_path == null)
			return false;
		
		context.add_package (pkg);
		context.add_source_file (new SourceFile (context, package_path, true));
		
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
}
