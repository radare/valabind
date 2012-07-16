/* Copyleft 2009-2012 -- pancake // nopcode.org */

using Vala;

public class SwigWriter : ValabindWriter {
	public bool cxx_mode;
	public GLib.List<string> includefiles = new GLib.List<string>();
	public GLib.List<Method> methods;
	string classname = "";
	string classcname;
	string externs = "";
	string statics = "";
	string extends = "";
	string enums = "";
	string vectors = "";
	string ?ns_pfx;
	string nspace = "";

	// FIXME duplicate from NodeFFIWriter
	string sep (string str, string separator) {
		if (str.length == 0)
			return str;     
		char last = str[str.length-1];
		if (last != '(' && last != '[' && last != '{')
			return str+separator;
		return str;
	}

	public SwigWriter (bool cxx_mode) {
		this.cxx_mode = cxx_mode;
	}

	public override string get_filename (string base_name) {
		return base_name+".i";
	}

	string get_alias (string? name) {
		if (name == null) {
			warning ("get_alias with null name");
			return "";
		}
		string oname = name;
		switch (name) {
		/*
		   case "use":
		   return "_use";
		 */
		case "break":
			name = "_break";
			break;
		case "cmd":
			name = "_cmd";
			break;
		case "def":
			name = "_def";
			break;
		case "print":
			name = "_print";
			break;
		case "delete":
			name = "_delete";
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
			warning ("%s.%s method renamed to %s.%s".printf (
						classname, oname, classname, name));
		return name;
	}

	string get_ctype (string _type) {
		string type = _type;
		string? iter_type = null;
		if (type == "null")
			error ("Cannot resolve type");
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*";
		type = type.replace (".", "");
		// ugly hack here //
		if (is_generic_hack (type)) {
			int ptr = type.index_of ("<");
			iter_type = (ptr==-1)?type:type[ptr:type.length];
			iter_type = iter_type.replace ("<", "");
			iter_type = iter_type.replace (">", "");
			iter_type = iter_type.replace (nspace, "");
			type = type.split ("<", 2)[0];
			//if (iter_type == "string")
			//    iter_type = "const char*";
			//if (type == "std::vector<string>")
			//    type = "std::vector<const char*>";
		}
		type = type.replace ("?","");

		switch (type) {
		case "std::vector<string>":
			return "std::vector<const char*>";
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
		case "string*":
			return "char *"; // ??? 
		case "guint":
			return "unsigned int";
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
			return "bool"; // XXX bool?
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

	public override void visit_constant (Constant c) {
		var cname = CCodeBaseModule.get_ccode_name (c);
		extends += "%immutable "+c.name+";\n";
		extends += "static const char *"+c.name+" = "+cname+";\n";
	}

	public override void visit_field (Field f) {
		if (f.get_ctype () == null) {
			//warning ("Cannot resolve type for field '%s'".printf (f.get_cname ()));
		} else {
			var cname = CCodeBaseModule.get_ccode_name (f);
			warning ("Type for "+cname+"\n");
		}
		//if (f.access == Accessibility.PRIVATE)
		//    print ("---> field is private XXX\n");
		//if (CCodeBaseModule.get_ccode_array_length (f))
		//    print ("---> array without length\n");
	}

	public override void visit_struct (Struct s) {
		/* TODO: implement struct visitor here */
	}

	public override void visit_class (Class c) {
		classname = ns_pfx+c.name;
		classcname = CCodeBaseModule.get_ccode_name (c);
		process_includes (c);
		if (context.profile == Profile.GOBJECT) {
			classname = "%s%s".printf (nspace, classname);
			extends += "typedef struct _%s {\n%%extend {\n".printf (classcname);
		} else extends += "%%extend %s {\n".printf (classname);
		foreach (Enum e in c.get_enums ())
			e.accept (this);
		foreach (Field f in c.get_fields ())
			f.accept (this);
		if (CCodeBaseModule.is_reference_counting (c)) {
			string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
			if (freefun != null && freefun != "")
				extends += "  ~%s%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
		} else {
			string? freefun = CCodeBaseModule.get_ccode_free_function (c);
			if (freefun != null && freefun != "")
				extends += "  ~%s%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
		}
		foreach (Method m in c.get_methods ())
			m.accept (this);
		foreach (Struct s in c.get_structs ())
			s.accept (this);
		foreach (Class k in c.get_classes ())
			k.accept (this);
		if (context.profile == Profile.GOBJECT) extends += "};\n} %s;\n".printf (classname);
		else extends += "};\n";
		classname = "";
	}

	/// new void visit_enum (Enum e, string pfx="") {
	// that pfx thing looks wrong
	// "that pfx thing" is for the C program that outputs the enum code
	// everything else is context-based, so only the name is required
	// but this needs absolute property names.
	// that's node-ffi specific anyway, just rename the current methods
	// to visit_*

	public override void visit_enum (Enum e) {
		var enumname = (classname + e.name).replace(".","");
		var tmp = "%{\n";
		enums += "/* enum: %s (%s) */\n".printf (
				e.name, CCodeBaseModule.get_ccode_name (e));
		enums += "enum %s {\n".printf (enumname);
		tmp += "#define %s long int\n".printf (enumname); // XXX: Use cname?
		foreach (var v in e.get_values ()) {
			enums += "  %s_%s,\n".printf (e.name, v.name);
			tmp += "#define %s_%s %s\n".printf (e.name, v.name, 
					CCodeBaseModule.get_ccode_name (v));
		}
		enums += "};\n";
		enums = tmp + "%}\n"+enums;
	}


	// another fugly hack, see get_type in node-ffi for sparkly clean implementation <3
	inline bool is_generic_hack(string type) {
		return (cxx_mode && type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	inline bool is_generic(DataType type) {
		return (type.get_type_arguments ().size >0);
	}

	public override void visit_method (Method m) {
		bool first = true;
		string cname = CCodeBaseModule.get_ccode_name (m);
		string alias = get_alias (m.name);
		string ret;
		string def_args = "";
		string call_args = "";
		bool void_return;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		ret = m.return_type.to_string ();
		if (is_generic (m.return_type))
			ret = get_ctype (ret);
		else ret = get_ctype (CCodeBaseModule.get_ccode_name (m.return_type));
		if (ret == null)
			error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");

		if (m.is_private_symbol ())
			return;

		string applys = "";
		string clears = "";
		string pfx;
		foreach (var foo in m.get_parameters ()) {
			string arg_name = get_alias (foo.name);
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null)
				continue;
			string? arg_type = get_ctype (CCodeBaseModule.get_ccode_name (bar));

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

				if (arg_type.index_of ("*") == -1)
					arg_type += "*";
				applys += "  %%apply %s %s { %s %s };\n".printf (
						arg_type, var_name, arg_type, arg_name);
				clears += "  %%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args += "%s%s".printf (pfx, arg_name);
			def_args += "%s%s %s".printf (pfx, arg_type, arg_name);
		}

		/* object oriented shit */
		if (classname == "") {
			externs += "extern %s %s (%s);\n".printf (ret, cname, def_args);
		} else {
			if (is_constructor) {
				externs += "extern %s* %s (%s);\n".printf (classcname, cname, def_args);
				extends += applys;
				extends += "  %s (%s) {\n".printf (classname, def_args);
				if (context.profile == Profile.GOBJECT)
					extends += "    g_type_init ();\n";
				extends += "    return %s (%s);\n  }\n".printf (cname, call_args);
				extends += clears;
			} else {
				if (is_static)
					statics += "extern %s %s (%s);\n".printf (ret, cname, def_args);
				else {
					if (call_args == "")
						call_args = "self";
					else call_args = "self, " + call_args;
				}
				externs += "extern %s %s (%s*, %s);\n".printf (ret, cname, classname, def_args);
				extends += applys;
				if (ret == "std::vector<string>") {
					warning ("std::vector<string> is not supported yet");
					return;
				}
				if (is_static)
					extends += "  static %s %s (%s) {\n".printf (ret, alias, def_args);
				else extends += "   %s %s (%s) {\n".printf (ret, alias, def_args);
				if (cxx_mode && ret.index_of ("std::vector") != -1) {
					int ptr = ret.index_of ("<");
					string iter_type = (ptr==-1)?ret:ret[ptr:ret.length];
					iter_type = iter_type.replace ("<", "");
					iter_type = iter_type.replace (">", "");
					// TODO: Check if iter type exists before failing
					//       instead of hardcoding the most common type '<G>'
					// TODO: Do not construct a generic class if not supported
					//       instead of failing.
					if (iter_type == "G*") /* No generic */
						error ("Fuck, no <G> type support.\n");
					// TODO: Do not recheck the return_type
					if (m.return_type.to_string ().index_of ("RFList") != -1) {
						// HACK
						extends += "    %s ret;\n".printf (ret);
						extends += "    void** array;\n";
						extends += "    %s *item;\n".printf (iter_type);
						extends += "    array = %s (%s);\n".printf (cname, call_args);
						extends += "    r_flist_rewind (array);\n";
						extends += "    while (*array != 0 && (item = (%s*)(*array++)))\n".printf (iter_type);
						extends += "        ret.push_back(*item);\n";
						extends += "    return ret;\n";
						extends += "  }\n";
					} else if (m.return_type.to_string ().index_of ("RList") != -1) {
						// HACK
						ret = ret.replace ("string", "const char*");
						//ret = get_ctype (ret); 
						extends += "    %s ret;\n".printf (ret);
						extends += "    RList *list;\n";
						extends += "    RListIter *iter;\n";
						extends += "    %s *item;\n".printf (iter_type);
						extends += "    list = %s (%s);\n".printf (cname, call_args);
						extends += "    if (list)\n";
						extends += "    for (iter = list->head; iter && (item = (%s*)iter->data); iter = iter->n)\n".printf (iter_type);
						extends += "        ret.push_back(*item);\n";
						extends += "    return ret;\n";
						extends += "  }\n";
					}
					vectors += "  %%template(%sVector) std::vector<%s>;\n".printf (
							iter_type, iter_type);
				} else {
					extends += "    %s %s (%s);\n  }\n".printf (
							void_return?"":"return", cname, call_args);
				}
				extends += clears;
			}
		}
	}

	public override void visit_namespace (Namespace ns) {
		string name = ns.get_full_name ();
		bool use = use_namespace (ns);
		if (use)
			ns_pfx = name+ ".";
		if (ns_pfx != null)
			process_includes (ns);
		foreach (var n in ns.get_namespaces ())
			n.accept (this);
		if (ns_pfx != null) {
			foreach (Constant c in ns.get_constants ())
				c.accept (this);
			foreach (Field f in ns.get_fields ())
				f.accept (this);
			foreach (Enum e in ns.get_enums ())
				e.accept (this);
			foreach (Struct s in ns.get_structs ())
				s.accept (this);
			foreach (Class c in ns.get_classes ())
				c.accept (this);
			foreach (Method m in ns.get_methods ())
				m.accept (this);
		}
		if (use)
			ns_pfx = null;
	}

	public override void write (string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (file));
		context.root.accept (this);
		stream.printf ("%%module %s\n%%{\n", modulename);
		if (!cxx_mode) {
			stream.printf (
					"#define bool int\n"+
					"#define true 1\n"+
					"#define false 0\n");
		}
		if (includefiles.length () > 0) {
			if (cxx_mode)
				stream.printf ("extern \"C\" {\n");
			foreach (var inc in includefiles)
				stream.printf ("#include <%s>\n", inc);
			if (cxx_mode)
				stream.printf ("}\n#include <vector>\n");
		}
		stream.printf ("%%}\n");
		foreach (var inc in includefiles)
			stream.printf ("%%include <%s>\n", inc);
		if (cxx_mode) {
			stream.printf ("%%include \"std_vector.i\"\n\n");
			if (vectors != "")
				stream.printf ("namespace std {\n%s}\n", vectors);
		}

		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", extends);
	}
}

