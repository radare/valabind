/* Copyleft 2009-2012 -- pancake // nopcode.org */

using Vala;

public class ValabindWriter : CodeVisitor {
	public string modulename;
	public bool pkgmode;
	public string pkgname;
	[CCode (array_length = false, array_null_terminated = true)]
	public string[] include_dirs;
	[CCode (array_length = false, array_null_terminated = true)]
	public string[] namespaces;
	protected CodeContext context = new CodeContext ();
	protected string vapidir;
	protected GLib.List<string> source_files = new GLib.List<string> ();

	public ValabindWriter () {
	}
	
	public void init (string vapidir, string profile) {
		CodeContext.push (context);
		this.vapidir = vapidir;
	#if VALA_0_12
		context.vapi_directories = { vapidir };
	#endif
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
		case "posix":
		default:
			context.profile = Profile.POSIX;
			context.add_define ("POSIX");
			break;
		}
	}

	public void parse () {
		var parser = new Parser ();
		parser.parse (context);
		if (!check ())
			error ("Problems found, aborting...");
	}

	public bool check () {
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
		notice ("Adding dependency "+pkg);
		return context.add_external_package (pkg);
	}

	public bool add_source_file (string path) {
		if (path == "") {
			error ("Missing path to source vapi");
			return false;
		}
		path.replace (".vapi", "");
		foreach (string f in source_files)
			if (path == f)
				return false;

		bool found = FileUtils.test (path, FileTest.IS_REGULAR);
		if (found) {
			if (!pkgmode) {
			#if VALA_0_12
				context.add_source_file (new SourceFile (context, SourceFileType.PACKAGE, path));
			#else
				context.add_source_file (new SourceFile (context, path, true));
			#endif
			}
			source_files.append(path);
		} else if (!add_package (context, path))
			error ("Cannot find '%s'".printf (path));
		return found;
	}

	/* Ripped from Vala Compiler */
	private bool add_package (CodeContext context, string pkg) {
		if (pkg == "") {
			warning ("Empty add_package()?");
			return true;
		}
		notice ("Adding dependency package "+pkg);

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
			warning ("Cannot find package path '%s'".printf (pkg));
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
				Report.error (null, "Unable to read dependency file: %s".printf (e.message));
			}
		}
		return true;
	}
	
	protected bool use_namespace (Namespace ns) {
		if (namespaces == null)
			return true;
		
		string name = ns.get_full_name ();
		foreach (string i in namespaces)
			if(name == i)
				return true;
		return false;
	}
	
	public virtual void write (string file) {
		error ("ValabindWriter.write not implemented");
	}
	
	public virtual string get_filename (string base_name) {
		warning ("ValabindWriter.get_filename not implemented");
		return base_name;
	}

	/*public void emit_vapi (string? output, string file) {
		var vapi_writer = new CodeWriter ();
		vapi_writer.write_file (context, file);
	}*/
}
