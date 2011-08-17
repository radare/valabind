/* Copyleft 2011 -- pancake // nopcode.org */

using Vala;

public class GirWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public bool show_externs;
	public bool glib_mode;
	public bool cxx_mode;
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
	private string enums;
	private string vectors;
	private string nspace;
	private string modulename;

	public GirWriter (string name) {
		enums = "";
		statics = "";
		externs = "";
		extends = "";
		vectors = "";
		classname = "";
		this.modulename = name;
		this.includefiles = new GLib.List<string>();
	}

	private string get_alias (string name) {
		string oname = name;
		switch (name) {
/*
		case "use":
			return "_use";
*/
		case "cmd":
			name = "_cmd";
			break;
		case "def":
			name = "_def";
			break;
		case "print":
			name = "_print";
			break;
		case "del":
			name = "_del";
			break;
		case "from":
			name = "_from";
			break;
		case "continue":
			name = "cont";
			break;
		}
		if (name != oname)
			ValabindCompiler.warning ("%s.%s method renamed to %s.%s".printf (
				classname, oname, classname, name));
		return name;
	}

	private string get_ctype (string _type) {
		string type = _type;
		string? iter_type = null;
		if (type == "null")
			ValabindCompiler.error ("Cannot resolve type");
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*";
		type = type.replace (".", "");
		if (is_generic (type)) {
			int ptr = type.index_of ("<");
			iter_type = (ptr==-1)?type:type[ptr:type.length];
			iter_type = iter_type.replace ("<", "");
			iter_type = iter_type.replace (">", "");
			iter_type = iter_type.replace (nspace, "");
			type = type.split ("<", 2)[0];
		}
		type = type.replace ("?","");

		switch (type) {
		case "const gchar*":
			return "const char*";
		case "G": /* generic type :: TODO: review */
		case "gconstpointer":
		case "gpointer":
	 		return "void*";
		case "gdouble":
			return "double";
		case "gfloat":
			return "float";
		case "break":
			return "_break";
		case "ut8":
		case "uint8":
		case "guint8":
			return "unsigned char";
		case "gchar**":
			return "char **";
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
			return "string";
			//return "char *"; // ??? 
		case "gint":
	 		return "int";
		case "glong":
	 		return "long";
		case "st64":
		case "int64":
		case "gint64":
			return "long long";
		case "ut64":
		case "uint64":
		case "guint64":
			return "unsigned long long";
		/* XXX swig does not support unsigned char* */
		case "uint8*":
		case "guint8*":
			return "unsigned char*";
		case "guint16":
		case "uint16":
			return "unsigned short";
		case "ut32":
		case "uint32":
		case "guint32":
			return "unsigned int";
		case "bool": // no conversion needed
		case "gboolean":
			return "gboolean";
		case "RFList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
		case "RList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
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
		foreach (var foo in CCodeBaseModule.get_ccode_header_filenames (s).split (",")) {
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

	public void walk_field (Field f) {
		var name = CCodeBaseModule.get_ccode_name (f);
		var type = f.variable_type.to_string ();
		type = get_ctype (type);
		externs += "    <field name=\""+name+"\" type=\""+type+"\"/>\n";
	}

	public void walk_struct (string pfx, Struct s) {
		var name = s.name;
		externs += "  <struct name=\""+name+"\">\n"; // TODO: parent="" type-name="" get-type=""
		/* TODO: refactor to walk_struct */
		foreach (var m in s.get_methods ())
			walk_method (m);
		foreach (var f in s.get_fields ())
			walk_field (f);
		externs += "  </struct>\n";
	}

	public void walk_class (string pfx, Class c) {
		foreach (var k in c.get_classes ())
			walk_class (c.name, k);
		classname = pfx+c.name;
		classcname = CCodeBaseModule.get_ccode_name (c);
		process_includes (c);
		if (glib_mode)
			classname = "%s%s".printf (nspace, classname);
		externs += "  <object name=\""+classname+"\">\n"; // TODO: parent="" type-name="" get-type=""
// TODO: print ("PARENT FOR "+classname+" IS: "+c.parent_node.type_name+"\n");
		// parent=\"\"
		foreach (var e in c.get_enums ())
			walk_enum (e);
		foreach (var f in c.get_fields ())
			walk_field (f);
/*
		if (c.is_reference_counting ()) {
			string? freefun = c.get_unref_function ();
			if (freefun != null)
				extends += "  ~%s%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
		} else {
			string? freefun = c.get_free_function ();
			if (freefun != null)
				extends += "  ~%s%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
		}
*/
		foreach (var m in c.get_methods ())
			walk_method (m);
		externs += "  </object>\n";
		classname = "";
	}

	public void walk_enum (Vala.Enum e) {
		var enumname = classname + e.name;
		var tmp = "  <enum name=\""+enumname+"\">\n"; // type-name=\""+e.name+"\" get-type=\"\">\n";
		//enums += "/* enum: %s (%s) */\n".printf ( e.name, e.get_cname ());
		//enums += "enum %s {\n".printf (enumname);
		//tmp += "#define %s long int\n".printf (enumname); // XXX: Use cname?
		foreach (var v in e.get_values ()) {
                        tmp += "    <member name=\""+e.name+"\" value=\""+
				CCodeBaseModule.get_ccode_name (v)+"\"/>\n";
			//enums += "  %s_%s,\n".printf (e.name, v.name);
			//tmp += "#define %s_%s %s\n".printf (e.name, v.name, v.get_cname ());
		}
		tmp += "  </enum>\n";
		enums = tmp + "\n" + enums;
	}

	private inline bool is_generic(string type) {
		return (cxx_mode && type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	public void walk_method (Method m) {
		//bool first = true;
		string cname = CCodeBaseModule.get_ccode_name (m);
		string alias = get_alias (m.name);
		string ret, vret;
		bool void_return;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		ret = vret = m.return_type.to_string ();
		if (is_generic (ret)) ret = get_ctype (vret);
		else ret = get_ctype (CCodeBaseModule.get_ccode_name (m.return_type));
		if (ret == null)
			ValabindCompiler.error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");

		if (m.is_private_symbol ())
			return;

		string type = is_static?"function":"method";
		if (classname != "" && !is_static)
			type = "method";
		if (is_constructor)
			type = "constructor";
		//externs += "<"+type+" name=\""+alias+"\" c:identifier=\""+cname+"\">\n";
		externs += "<"+type+" name=\""+alias+"\" c:identifier=\""+cname+"\">\n";
		if (void_return) {
			externs += "  <return-type type=\"void\"/>\n";
		} else {

			var rtype = get_ctype (ret);
			externs += "  <return-type type=\""+rtype+"\" />\n";
/*
			externs += "    <return-value transfer-ownership=\"none\">\n";
			externs += "      <type name=\""+vret+"\" c:type=\""+ret+"\"/>\n";
			externs += "    </return-value>\n";
*/
		}

		var parameters = m.get_parameters ();
		if (parameters.size>0) {
			externs += "  <parameters>\n";
			foreach (var foo in parameters) {
				string arg_name = foo.name;
				DataType? bar = foo.variable_type;
				if (bar == null)
					continue;
				string? arg_type = bar.to_string ();
				string? arg_ctype = get_ctype (CCodeBaseModule.get_ccode_name (bar));
				externs += "    <parameter name=\""+arg_name+"\" transfer-ownership=\"none\">\n";
				externs += "      <type name=\""+arg_type+"\" c:type=\""+arg_ctype+"\"/>\n";
				externs += "    </parameter>\n";
			}
			externs += "  </parameters>\n";
		}
		externs += "</"+type+">\n"; //function>\n";
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;

		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);

externs += "<namespace version=\"1.0\" name=\""+nspace+"\">\n";
		//if (pkgmode && sr.file.filename.index_of (pkgname) == -1)
		//	return;
		foreach (var f in ns.get_fields ())
			walk_field (f);
		foreach (var e in ns.get_enums ())
			walk_enum (e);
		foreach (var s in ns.get_structs ())
			walk_struct ("", s);
		foreach (var m in ns.get_methods ())
			walk_method (m);
		foreach (var c in ns.get_classes ())
			walk_class ("", c);
		//ns.accept_children (this);
externs += "</namespace>\n";
	}

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		if (this.stream == null)
			error ("Cannot open %s for writing".printf (filename));
		this.context = context;
		context.accept (this);
		stream.printf ("<?xml version=\"1.0\"?>\n");
		stream.printf ("<!-- automatically generated with valabind -->\n");
		stream.printf ("<!-- To compile: g-ir-compiler foo.gir > foo.typelib -->\n");
		stream.printf ("<repository version=\"1.2\"\n"+
			"	xmlns=\"http://www.gtk.org/introspection/core/1.0\"\n"+
			"	xmlns:c=\"http://www.gtk.org/introspection/c/1.0\"\n"+
			"	xmlns:glib=\"http://www.gtk.org/introspection/glib/1.0\">\n");
		stream.printf ("  <namespace version=\"1.0\" name=\""+modulename+"\">\n");
		if (includefiles.length () > 0)
			foreach (var inc in includefiles)
				stream.printf ("  <c:include name=\"%s\"/>\n", inc);

		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", externs);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", extends);

		stream.printf ("  </namespace>\n");
		stream.printf ("</repository>\n");

		this.stream = null;
	}
}
