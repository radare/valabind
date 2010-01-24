/* Copyleft 2009-2010 -- pancake // nopcode.org */

using Vala;
using Posix.exit;

public class SwigWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public bool show_externs;
	public bool glib_mode;
	public string[] files;
	public GLib.List<string> includefiles;
	public GLib.List<Method> methods;
	private CodeContext context;
	private FileStream? stream;
	private string classname;
	private string classcname;
	private string externs;
	private string statics;
	private string extends;
	private string applys;
	private string enums;
	private string nspace;
	private string modulename;

	public SwigWriter (string name) {
		classname = "";
		statics = "";
		externs = "";
		extends = "";
		applys = "";
		enums = "";
		this.modulename = name;
		this.includefiles = new GLib.List<string>();
	}

	private string get_alias (string name) {
		switch (name) {
/*
		case "use":
			return "_use";
*/
		case "cmd":
			return "_cmd";
		case "print":
			return "_print";
		case "del":
			return "_del";
		case "from":
			return "_from";
		case "continue":
			return "cont";
		}
		// TODO: display warning when changing a method/variable name
		return name;
	}

	private string get_ctype (string _type) {
		string type = _type;
		if (type == "null") {
			stderr.printf ("Cannot resolve type\n");
			Posix.exit (1);
		}
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*";
		if (type.str (".") != null)
			type = type.replace (".", "");
		type = type.replace ("?","");

		switch (type) {
		case "G": /* generic type :: TODO: review */
		case "gpointer":
	 		return "void*";
		case "ut8":
		case "uint8":
		case "guint8":
			return "unsigned char";
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
			return "char *"; // ??? 
		case "gint":
	 		return "int";
		case "glong":
	 		return "long";
		case "ut64":
		case "uint64":
		case "guint64":
			return "unsigned long long";
		/* XXX swig does not support unsigned char* */
		case "uint8*":
		case "guint8*":
			return "char*"; //"unsigned char*";
		case "guint16":
		case "uint16":
			return "unsigned short";
		case "ut32":
		case "uint32":
		case "guint32":
			return "unsigned int";
		case "bool": // no conversion needed
		case "gboolean":
			return "bool"; // XXX bool?
		}
		return type;
	}

	private bool is_target_file (string path) {
		foreach (var file in files)
			if (file == path)
				return true;
		return false;
	}

	public override void visit_source_file (SourceFile source) {
		if (is_target_file (source.filename))
			source.accept_children (this);
	}

	public void process_includes (Symbol s) {
		foreach (var foo in s.get_cheader_filenames ()) {
			var include = true;
			foreach (var inc in includefiles) {
				if (inc == foo) {
					include = false;
					break;
				}
			}
			if (include)
				includefiles.prepend (foo);
		}
	}

	public void walk_class (Class c) {
		classname = c.name;
		classcname = c.get_cname ();

		process_includes (c);
		/* {
			var dest = c.destructor;
			var sdest = c.static_destructor;
			var cdest = c.class_destructor;
			print ("DESTRUCTOR: %p %p %p\n", dest, sdest, cdest);
		} */
		if (glib_mode)
			classname = "%s%s".printf (nspace, classname);

		if (glib_mode) extends += "typedef struct _%s {\n%%extend {\n".printf (classcname);
		else extends += "%%extend %s {\n".printf (classname);
		foreach (var e in c.get_enums ())
			walk_enum (e);
		foreach (var m in c.get_methods ())
			walk_method (m);
		if (glib_mode) extends += "};\n} %s;\n".printf (classname);
		else extends += "};\n";
		classname = "";
	}

	public void walk_enum (Vala.Enum e) {
		var enumname = classname + e.name;
		var tmp = "%{\n";
		enums += "/* enum: %s (%s) */\n".printf (
			e.name, e.get_cname ());
		enums += "#define %s int\n".printf (enumname);
		enums += "enum {\n";
		foreach (var v in e.get_values ()) {
			enums += "  %s_%s,\n".printf (e.name, v.name);
			tmp += "#define %s_%s %s\n".printf (e.name, v.name, v.get_cname ());
		}
		extends += enums + "};\n";
		extends += tmp + "%}\n";
		enums = "";
	}

	public void walk_method (Method m) {
		bool first = true;
		string cname = m.get_cname ();
		string name = m.name;
		string alias = get_alias (m.name);
		string ret = get_ctype (m.return_type.to_string ());
		string def_args = "";
		string call_args = "";
		bool void_return = (ret == "void");
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (name == ".new"); // weak way to check it?

		if (m.is_private_symbol ())
			return;

		string pfx;
		foreach (var foo in m.get_parameters ()) {
			string arg_name = foo.name;
			DataType? bar = foo.parameter_type;
			if (bar == null)
				continue;
			string arg_type = get_ctype (bar.get_cname ());

			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";

			/* TODO: move to get_ctype */
			if (foo.direction != ParameterDirection.IN) {
				var var_name = "";
				if (foo.direction == ParameterDirection.OUT)
					var_name = "OUTPUT";
				else
				if (foo.direction == ParameterDirection.REF)
					var_name = "INOUT";

				if (arg_type.str ("*") == null)
					arg_type += "*";
				applys += "%%apply %s %s { %s %s };\n".printf (
					arg_type, var_name, arg_type, arg_name);
			}
			call_args += "%s%s".printf (pfx, arg_name);
			def_args += "%s%s %s".printf (pfx, arg_type, arg_name);
		}

		/* object oriented shit */
		if (classname != "") {
			if (is_constructor) {
				externs += "extern %s* %s (%s);\n".printf (classcname, cname, def_args);
				extends += "  %s (%s) {\n".printf (classname, def_args);
				if (glib_mode)
					extends += "    g_type_init ();\n";
				extends += "    return %s (%s);\n  }\n".printf (cname, call_args);
			} else {
				if (is_static)
					statics += "extern %s %s (%s);\n".printf (ret, cname, def_args);
				else {
					if (call_args == "")
						call_args = "self";
					else call_args = "self, " + call_args;
				}
				externs += "extern %s %s (%s*, %s);\n".printf (ret, cname, classname, def_args);
				extends += "  %s %s (%s) {\n".printf (ret, alias, def_args);
				extends += "    %s %s (%s);\n  }\n".printf (
					void_return?"":"return", cname, call_args);
			}
		} else {
			externs += "extern %s %s (%s);\n".printf (ret, cname, def_args);
		}
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;

		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);

		if (pkgmode && sr.file.filename.str (pkgname) == null)
			return;

		foreach (var e in ns.get_enums ())
			walk_enum (e);
		foreach (var c in ns.get_structs ()) {
			/* TODO: refactor to walk_struct */
			foreach (var m in c.get_methods ())
				walk_method (m);
		}
		foreach (var m in ns.get_methods ())
			walk_method (m);
		foreach (var c in ns.get_classes ())
			walk_class (c);

		//ns.accept_children (this);
	}

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		if (this.stream == null) {
			error ("Cannot open %s for writing".printf (filename));
			return;
		}
		this.context = context;
		context.accept (this);

		stream.printf ("%%module %s\n", modulename);

		stream.printf ("%%{\n");
		stream.printf ("#define bool int\n");
		stream.printf ("#define true 1\n");
		stream.printf ("#define false 0\n");
		if (includefiles.length () > 0) {
			foreach (var inc in includefiles)
				stream.printf ("#include <%s>\n", inc);
		}
		stream.printf ("%%}\n");
		foreach (var inc in includefiles)
			stream.printf ("%%include <%s>\n", inc);

		stream.printf ("%s\n", enums);
		if (show_externs)
			stream.printf ("%s\n", externs);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", applys);
		stream.printf ("%s\n", extends);

		this.stream = null;
	}
}
