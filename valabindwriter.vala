/* Copyleft 2009-2013 -- pancake // nopcode.org */

using Vala;

public class ValabindWriter : CodeVisitor {
	public string modulename;
	public string library;
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

	public void init (string vapidir, bool glibmode) {
		CodeContext.push (context);
		this.vapidir = vapidir;
		context.vapi_directories = { vapidir };
		add_package (context, "glib-2.0");
		add_package (context, "gobject-2.0");
		/* vala 0.17 only support gobject profile */
		if (glibmode)
			context.add_define ("GOBJECT");
		// required to avoid ugly runtime errors
		context.profile = Profile.GOBJECT;
	}

	public void parse () {
		var parser = new Parser ();
		parser.parse (context);
		if (!check ())
			error ("Problems found, aborting...");
	}

	public bool check () {
		context.check ();
		return (context.report.get_errors () == 0);
	}

	public void add_define (string define) {
		notice ("Symbol defined "+define);
		context.add_define(define);
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
			if (!pkgmode)
				context.add_source_file (new SourceFile (
					context, SourceFileType.PACKAGE, path));
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

		// ignore multiple occurences of the same package
		if (context.has_package (pkg))
			return true;

		notice ("Adding dependency package "+pkg);

		var package_path = context.get_vapi_path (pkg);
		if (package_path == null) {
			warning ("Cannot find package path '%s'".printf (pkg));
			return false;
		}

		if (pkgmode)
			add_source_file (package_path);
		context.add_source_file (new SourceFile (context,
			SourceFileType.PACKAGE, package_path));
		context.add_package (pkg);

		var deps_filename = Path.build_filename (Path.get_dirname (
			package_path), "%s.deps".printf (pkg));
		if (FileUtils.test (deps_filename, FileTest.EXISTS)) {
			try {
				string deps_content;
				size_t deps_len;

				FileUtils.get_contents (deps_filename,
					out deps_content, out deps_len);
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
