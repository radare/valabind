/* Copyleft 2009-2011 -- pancake // nopcode.org */

using Vala;

public class ValabindCompiler {
	string vapidir;
	string modulename;
	CodeContext context;
	public bool pkgmode;
	public string pkgname;
	string[] source_files;

	public ValabindCompiler (string modulename, string vapidir, string profile) {
		context = new CodeContext ();
		CodeContext.push (context);
		this.modulename = modulename;
		this.vapidir = vapidir;
	#if VALA_0_12
		context.vapi_directories = { vapidir };
	#endif
		source_files = null;
		add_package (context, "glib-2.0");
		add_package (context, "gobject-2.0");
		switch (profile) {
		case "gobject":
			context.profile = Profile.GOBJECT;
			context.add_define ("GOBJECT");
			break;
		case "dova":
			context.profile = Profile.DOVA;
			context.add_define ("DOVA");
			break;
		default:
		case "posix":
			context.profile = Profile.POSIX;
			context.add_define ("POSIX");
			break;
		}
	}

	public void parse () {
		var parser = new Parser ();
		parser.parse (context);
		if (!init ())
			error ("valabind initialization failed");
	}

	public bool init () {
	#if VALA_0_12
		context.check ();
	#else
		var resolver = new SymbolResolver ();
		resolver.resolve (context);
		if (context.report.get_errors () != 0)
			return false;

		var analyzer = new SemanticAnalyzer ();
		analyzer.analyze (context);
		if (context.report.get_errors () != 0)
			return false;

		var flow_analyzer = new FlowAnalyzer ();
		flow_analyzer.analyze (context);
	#endif
		return (context.report.get_errors () == 0);
	}

	public bool add_external_package (string pkg) {
		return context.add_external_package (pkg);
	}

	public bool add_source_file (string path) {
		foreach (var f in source_files) {
			if (path == f)
				return false;
		}

		bool ret = FileUtils.test (path, FileTest.IS_REGULAR);
		if (ret) {
			if (!pkgmode) {
			#if VALA_0_12
				context.add_source_file (new SourceFile (context, SourceFileType.PACKAGE, path));
			#else
				context.add_source_file (new SourceFile (context, path, true));
			#endif
			}
			source_files += path;
		} else
		if (!add_package (context, path))
			ValabindCompiler.error ("Cannot find '%s'.\n".printf (path));
		return ret;
	}

	public void emit_vapi (string? output, string file) {
		var swig_writer = new CodeWriter ();
		swig_writer.write_file (context, file);
	}

	public void emit_gir (string file, bool show_externs, bool glibmode, bool cxxmode, string? include) {
		var gir_writer = new GirWriter (modulename);
		if (gir_writer != null) {
			/* TODO: why not just pass a ValabindCompiler reference to it? */
			gir_writer.pkgmode = pkgmode;
			gir_writer.pkgname = pkgname;
			if (include != null)
				gir_writer.includefiles.append (include);
			gir_writer.files = source_files;
			gir_writer.write_file (context, file);
		} else warning ("cannot create swig writer");
	}

	public void emit_gear (string file, bool show_externs, bool glibmode, bool cxxmode, string? include) {
		var gear_writer = new GearWriter (modulename);
		if (gear_writer != null) {
			/* TODO: why not just pass a ValabindCompiler reference to it? */
			gear_writer.pkgmode = pkgmode;
			gear_writer.pkgname = pkgname;
			if (include != null)
				gear_writer.includefiles.append (include);
			gear_writer.files = source_files;
			gear_writer.write_file (context, file);
		} else warning ("cannot create swig writer");
	}

	public void emit_cxx (string file, bool show_externs, bool glibmode, bool cxxmode, string? include) {
		var cxx_writer = new CxxWriter (modulename);
		if (cxx_writer != null) {
			/* TODO: why not just pass a ValabindCompiler reference to it? */
			cxx_writer.show_externs = show_externs;
			cxx_writer.glib_mode = glibmode;
			cxx_writer.cxx_mode = cxxmode;
			cxx_writer.pkgmode = pkgmode;
			cxx_writer.pkgname = pkgname;
			if (include != null)
				cxx_writer.includefiles.append (include);
			cxx_writer.files = source_files;
			cxx_writer.write_file (context, file);
		} else warning ("cannot create swig writer");
	}

	public void emit_swig (string file, bool show_externs, bool glibmode, bool cxxmode, string? include) {
		var swig_writer = new SwigWriter (modulename);
		if (swig_writer != null) {
			/* TODO: why not just pass a ValabindCompiler reference to it? */
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

	#if VALA_0_12
		var package_path = context.get_vapi_path (pkg);
	#else
		string[] vapi_directories = { vapidir };
		var package_path = context.get_package_path (pkg, vapi_directories);
	#endif
		if (package_path == null) {
			stderr.printf ("Cannot find package path '%s'", pkg);
			return false;
		}

		if (pkgmode)
			add_source_file (package_path);
	#if VALA_0_12
		context.add_source_file (new SourceFile (context, SourceFileType.PACKAGE, package_path));
	#else
		context.add_source_file (new SourceFile (context, package_path, true));
	#endif
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
