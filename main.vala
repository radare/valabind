using Vala;

public class SwigCompiler {
	CodeContext context;
	string[] source_files;

	public SwigCompiler () {
		context = new CodeContext ();
		init ();
	}

	public void parse () {
		var parser = new Parser ();
		parser.parse (context);
	}

	public bool init () {
//		add_package (context, "glib-2.0");
//		add_package (context, "gobject-2.0");

		/* warning about type_symbol stuff */
//		var analyzer = new SemanticAnalyzer ();
//		analyzer.analyze (context);

		/* analysis and checks */
		var resolver = new SymbolResolver ();
		resolver.resolve (context);

		/* the flow */
		var flow_analyzer = new FlowAnalyzer ();
		flow_analyzer.analyze (context);

		if (context.report.get_errors () > 0)
			return false;
		return true;
	}

	public bool add_source_file (string path) {
		var source = new SourceFile (context, path);
		context.add_source_file (source);
		source_files += path;
		return true;
	}

	public void emit_vapi (string file) {
		var swig_writer = new CodeWriter ();
		swig_writer.write_file (context, file);
	}

	public void emit_swig (string file) {
		var swig_writer = new SwigWriter ();
		swig_writer.files = source_files;
		swig_writer.write_file (context, file);
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
						if (!add_package (context, dep)) {
							Report.error (null, "%s, dependency of %s, not found in specified Vala API directories".printf (dep, pkg));
						}
					}
				}
			} catch (FileError e) {
				Report.error (null, "Unable to read dependency file: %s".printf (e.message));
			}
		}
		
		return true;
	}
}

void main (string[] args) {
	SwigCompiler sc = new SwigCompiler ();
	if (args.length > 1)
		sc.add_source_file (args[1]);
	else sc.add_source_file ("foo.vapi");

	sc.parse ();

	sc.emit_swig ("blah.i");
	sc.emit_vapi ("blah");
}
