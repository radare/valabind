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

	public SwigWriter (bool cxx_mode) {
		this.cxx_mode = cxx_mode;
	}

	public override string get_filename (string base_name) {
		return base_name+".i";
	}

	// FIXME duplicate from NodeFFIWriter
	void add_includes (Symbol s) {
		foreach (string i in CCodeBaseModule.get_ccode_header_filenames (s).split (",")) {
			bool include = true;
			foreach (string j in includefiles) {
				if (i == j) {
					include = false;
					break;
				}
			}
			if (include)
				includefiles.prepend (i);
		}
	}

	// FIXME duplicate from NodeFFIWriter
	string sep (string str, string separator) {
		if (str.length == 0)
			return str;     
		char last = str[str.length-1];
		if (last != '(' && last != '[' && last != '{')
			return str+separator;
		return str;
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

	string type_name (DataType type, bool ignoreRef=false) {
		if (type == null) {
			warning ("Cannot resolve type");
			return "__UNRESOLVED_TYPE_OH_PLEASE_KILL_ME_NOW__";
		}

		// HACK is this required?
		if (type is EnumValueType)
			return "long int";

		if (type is GenericType)
			return type.to_qualified_string ();

		if (type is PointerType)
			return type_name ((type as PointerType).base_type, true)+"*";

		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type);
			if (!array.fixed_length)
				return element+"*"; // FIXME should this be element+"[]"?
			return element+"[%d]".printf (array.length); // FIXME will this work?
		}

		string generic = "";
		foreach (DataType t in type.get_type_arguments ())
			generic = sep (generic, ", ") + type_name (t);
		// FIXME is this the right way to get the C type?
		string _type = CCodeBaseModule.get_ccode_name (type);//.to_string ();

		// HACK find a better way to remove generic type args
		_type = _type.split ("<", 2)[0];

		_type = _type.replace ("?","");
		_type = _type.replace ("unsigned ", "u");

		switch (_type) {
			// FIXME won't catch (std::vector)
			case "std::vector<string>":
				return "std::vector<const char*>";
			// FIXME won't catch (PointerType)
			case "const gchar*":
				return "const char*";
			case "gconstpointer":
			case "gpointer":
				return "void*";
			case "gdouble":
				return "double";
			case "gfloat":
				return "float";
			// HACK why?
			case "break":
				return "_break";
			case "ut8":
			case "uint8":
			case "guint8":
				return "unsigned char";
			case "gchar":
				return "char";
			case "string":
				return "char*";
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
			case "guint16":
			case "uint16":
				return "unsigned short";
			case "ut32":
			case "uint32":
			case "guint32":
				return "unsigned int";
			case "bool":
			case "gboolean":
				return "bool";
			// HACK needs proper generic support
			case "RList":
				if (generic != "")
					return "std::vector<"+generic+">";
				break;
		}
		return _type;
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
		add_includes (c);
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
		if (context.profile == Profile.GOBJECT)
			extends += "};\n} %s;\n".printf (classname);
		else extends += "};\n";
		classname = "";
	}

	public override void visit_enum (Enum e) {
		var enumname = (classname + e.name).replace(".","");
		var tmp = "%{\n";
		enums += "/* enum: %s (%s) */\n".printf (
				e.name, CCodeBaseModule.get_ccode_name (e));
		enums += "enum %s {\n".printf (enumname);
		// HACK use this or type_name?
		tmp += "#define %s long int\n".printf (enumname); // XXX: Use cname?
		foreach (var v in e.get_values ()) {
			enums += "  %s_%s,\n".printf (e.name, v.name);
			tmp += "#define %s_%s %s\n".printf (e.name, v.name, 
					CCodeBaseModule.get_ccode_name (v));
		}
		enums += "};\n";
		enums = tmp + "%}\n"+enums;
	}

	public override void visit_method (Method m) {
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

		ret = type_name (m.return_type);
		if (ret == null)
			error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");

		if (m.is_private_symbol ())
			return;

		string applys = "", clears = "";
		foreach (var foo in m.get_parameters ()) {
			string arg_name = get_alias (foo.name);
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null)
				continue;
			string? arg_type = type_name (bar);

			/* TODO: move to type_name */
			if (foo.direction != ParameterDirection.IN) {
				var var_name = "";
				if (foo.direction == ParameterDirection.OUT)
					var_name = "OUTPUT";
				else if (foo.direction == ParameterDirection.REF)
					var_name = "INOUT";

				if (arg_type.index_of ("*") == -1)
					arg_type += "*";
				applys += "  %%apply %s %s { %s %s };\n".printf (
						arg_type, var_name, arg_type, arg_name);
				clears += "  %%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args = sep(call_args, ", ") + arg_name;
			def_args = sep(def_args, ", ") +  arg_type + " " + arg_name;
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

				//BEGIN HACK HACK HACK DIE IN A FIRE
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
					if (m.return_type.to_string ().index_of ("RList") != -1) {
						//ret = type_name (ret);
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
				}
				//END HACK HACK HACK DIE IN A FIRE
				else
					extends += "    %s %s (%s);\n  }\n".printf (
							void_return?"":"return", cname, call_args);
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
			add_includes (ns);
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
		if (!cxx_mode)
			stream.printf (
					"#define bool int\n"+
					"#define true 1\n"+
					"#define false 0\n");
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

