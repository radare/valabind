/* Copyleft 2009-2012 -- pancake // nopcode.org */

using Vala;

public class SwigWriter : ValabindWriter {
	public bool cxx_mode;
	public GLib.List<string> includefiles = new GLib.List<string> ();
	public GLib.List<Method> methods;
	string classname = "";
	string statics = "";
	string structs = "";
	string extends = "";
	string enums = "";
	//string vectors = "";
	string ?ns_pfx;

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

	string get_alias (string oname) {
		string name = oname;
		switch (oname) {
			case "break":
			case "delete":
				name = "_"+oname;
				break;
			case "continue":
				name = "cont";
				break;
		}
		if (name != oname)
			warning ("%s.%s renamed to %s.%s".printf (classname, oname, classname, name));
		return name;
	}

	string type_name (DataType type, bool retType=false, bool ignoreRef=false) {
		if (type == null) {
			warning ("Cannot resolve type");
			return "__UNRESOLVED_TYPE_OH_PLEASE_KILL_ME_NOW__";
		}

		// HACK is this required?
		if (type is EnumValueType)
			return "long int";

		// HACK needs proper generic support
		if (type is GenericType)
			return "void*";
			//return type.to_qualified_string ();

		if (type is PointerType)
			return type_name ((type as PointerType).base_type, retType, true)+"*";

		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type, retType);
			if (!array.fixed_length)
				return element+"*"; // FIXME should this be element+"[]"?
			return element+"[%d]".printf (array.length); // FIXME will this work?
		}

		if (!ignoreRef && (type is ReferenceType)) {
			string unref_type = type_name (type, retType, true);
			// HACK just check for the string class instead (how?)
			if (unref_type == "char*" || unref_type == "const char*")
				return unref_type;
			// FIXME should it be & under C++?
			return unref_type+"*";
		}

		string generic = "";
		foreach (DataType t in type.get_type_arguments ())
			generic = sep (generic, ", ") + type_name (t);

		string _type = type.to_string ();

		// HACK find a better way to remove generic type args
		_type = _type.split ("<", 2)[0];

		_type = _type.replace (ns_pfx, "").replace (".", "");
		_type = _type.replace ("?","");
		_type = _type.replace ("unsigned ", "u");

		switch (_type) {
			case "bool":
			case "gboolean":
				return "bool";
			case "gconstpointer":
			case "gpointer":
				return "void*";
			case "gchar":
				return "char";
			case "gint":
				return "int";
			case "guint":
				return "unsigned int";
			case "glong":
				return "long";
			case "ut8":
			case "uint8":
			case "guint8":
				return "uint8_t";
			case "guint16":
			case "uint16":
				return "uint16_t";
			case "st32":
			case "int32":
			case "gint32":
				return "int32_t";
			case "ut32":
			case "uint32":
			case "guint32":
				return "uint32_t";
			case "st64":
			case "int64":
			case "gint64":
				return "int64_t";
			case "ut64":
			case "uint64":
			case "guint64":
				// HACK uint64_t doesn't work here because radare2 doesn't use the right type
				return "unsigned long long";
			case "gdouble":
				return "double";
			case "gfloat":
				return "float";
			case "string":
				return retType ? "const char*" : "char*";
			//case "const gchar*":
			//	return "const char*";
			// HACK needs proper generic support
			/*case "RList":
				if (generic != "")
					return "std::vector<"+generic+">";
				break;*/
		}
		return _type;
	}

	public override void visit_constant (Constant c) {
		var cname = CCodeBaseModule.get_ccode_name (c);
		extends += "%immutable "+c.name+";\n";
		extends += "static const char *"+c.name+" = "+cname+";\n";
	}

	public override void visit_field (Field f) {
		if (f.is_private_symbol ())
			return;
		// HACK don't output fields with C++ keywords as names.
		if (f.name == "class")
			return;
		string field = "";
		DataType type = f.variable_type;
		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type);
			if (!array.fixed_length)
				field = element + "* " + f.name; // FIXME should this be element+"[]"?
			field = element + " " + f.name + "[%d]".printf (array.length); // FIXME will this work?
		} else
			field = type_name (type) + " " + f.name;
		structs += "\t" + field + ";\n";
	}

	public override void visit_enum (Enum e) {
		add_includes (e);

		/*extends += "enum %s {\n".printf (e.name);
		foreach (var v in e.get_values ())
			extends += "\t%s = %s,\n".printf (v.name, CCodeBaseModule.get_ccode_name (v));
		extends += "};\n";*/
	}

	public override void visit_struct (Struct s) {
		add_includes (s);
		/* TODO: implement struct visitor here */
	}

	public override void visit_class (Class c) {
		add_includes (c);

		// FIXME does SWIG support actual namespaces?
		classname = c.get_full_name ().replace (ns_pfx, "").replace (".", "");
		string cname = CCodeBaseModule.get_ccode_name (c);

		structs += "typedef struct %s {\n".printf (cname);
		foreach (Field f in c.get_fields ())
			f.accept (this);
		structs += "} %s;\n".printf (classname);
		foreach (Enum e in c.get_enums ())
			e.accept (this);

		string? freefun = null;
		if (CCodeBaseModule.is_reference_counting (c))
			freefun = CCodeBaseModule.get_ccode_unref_function (c);
		else
			freefun = CCodeBaseModule.get_ccode_free_function (c);
		if (freefun == "")
			freefun = null;
		var methods = c.get_methods ();
		if (freefun != null || methods.size > 0) {
			extends += "%%extend %s {\n".printf (classname);
			if (freefun != null && freefun != "")
				extends += "\t~%s() {\n\t\t%s(self);\n\t}\n".printf (classname, freefun);
			foreach (Method m in methods)
				m.accept (this);
			extends += "};\n";
		}

		classname = "";

		foreach (Struct s in c.get_structs ())
			s.accept (this);
		foreach (Class k in c.get_classes ())
			k.accept (this);
	}

	public override void visit_method (Method m) {
		if (m.is_private_symbol ())
			return;

		add_includes (m);

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

		ret = type_name (m.return_type, true);
		if (ret == null)
			error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");


		string applys = "", clears = "";
		foreach (var foo in m.get_parameters ()) {
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null)
				continue;
			string arg_name = get_alias (foo.name);
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
				applys += "\t%%apply %s %s { %s %s };\n".printf (
						arg_type, var_name, arg_type, arg_name);
				clears += "\t%%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args = sep (call_args, ", ") + arg_name;
			def_args = sep (def_args, ", ") + arg_type + " " + arg_name;
		}

		/* object oriented shit */
		//if (classname != ""){
			if (is_constructor) {
				//externs += "extern %s* %s (%s);\n".printf (classcname, cname, def_args);
				extends += applys;
				extends += "\t%s (%s) {\n".printf (classname, def_args);
				if (context.profile == Profile.GOBJECT)
					extends += "\t\tg_type_init ();\n";
				extends += "\t\treturn %s (%s);\n\t}\n".printf (cname, call_args);
				extends += clears;
			} else {
				string func = "";
				//if (is_static)
					//statics += "extern %s %s (%s);\n".printf (ret, cname, def_args);
				//else {
				if (!is_static) {
					if (call_args == "")
						call_args = "self";
					else call_args = "self, " + call_args;
				}

				//externs += "extern %s %s (%s*, %s);\n".printf (ret, cname, classname, def_args);
				func += applys;

				if (is_static)
					func += "\tstatic %s %s(%s) {\n".printf (ret, alias, def_args);
				else func += "\t%s %s(%s) {\n".printf (ret, alias, def_args);

				//BEGIN HACK HACK HACK DIE IN A FIRE
				#if 0
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
						extends += "\t\t%s ret;\n".printf (ret);
						extends += "\t\tRList *list;\n";
						extends += "\t\tRListIter *iter;\n";
						extends += "\t\t%s *item;\n".printf (iter_type);
						extends += "\t\tlist = %s (%s);\n".printf (cname, call_args);
						extends += "\t\tif (list)\n";
						extends += "\t\tfor (iter = list->head; iter && (item = (%s*)iter->data); iter = iter->n)\n".printf (iter_type);
						extends += "\t\t\tret.push_back(*item);\n";
						extends += "\t\treturn ret;\n";
						extends += "\t}\n";
					}
					vectors += "\t%%template(%sVector) std::vector<%s>;\n".printf (
							iter_type, iter_type);
				}
				//END HACK HACK HACK DIE IN A FIRE
				else
				#endif
					func += "\t\t%s%s(%s);\n\t}\n".printf (void_return?"":"return ", cname, call_args);
				func += clears;

				if (classname == "") {
					statics += func;
					extends += "\tstatic %s %s(%s);\n".printf (ret, alias, def_args);
				} else
					extends += func;
			}
		//}
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
			//foreach (Field f in ns.get_fields ())
			//	f.accept (this);
			foreach (Enum e in ns.get_enums ())
				e.accept (this);
			foreach (Struct s in ns.get_structs ())
				s.accept (this);
			foreach (Class c in ns.get_classes ())
				c.accept (this);
			//foreach (Method m in ns.get_methods ())
			//	m.accept (this);
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
					"\t#define bool int\n"+
					"\t#define true 1\n"+
					"\t#define false 0\n");
		if (statics != "" || includefiles.length () > 0) {
			if (cxx_mode)
				stream.printf ("\textern \"C\" {\n");
			foreach (string inc in includefiles)
				stream.printf ("\t#include <%s>\n", inc);
			stream.printf ("%s", statics);
			if (cxx_mode)
				stream.printf ("\t}\n\t#include <vector>\n");
		}
		stream.printf ("%%}\n");

		//if (cxx_mode && vectors != "")
		//		stream.printf ("%%include \"std_vector.i\"\n\nnamespace std {\n%s}\n", vectors);

		stream.printf ("%s\n", structs);
		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", extends);
	}
}

