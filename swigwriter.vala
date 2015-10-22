/* Copyright 2009-2015 -- pancake, eddyb, ritesh */

using Vala;

public class SwigWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	bool cxx_mode;
	string statics = "";
	string structs = "";
	string extends = "";
	string enums = "";
	string vectors = "";
	string ?ns_pfx;

	public SwigWriter (bool cxx_mode) {
		this.cxx_mode = cxx_mode;
	}

	public override string get_filename (string base_name) {
		return base_name+".i";
	}

	// FIXME duplicate from NodeFFIWriter and ctypeswriter
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

		if (this.camelgetters) {
			if (oname.has_prefix ("set_")) {
				var capital = "%c".printf (oname[4].toupper ());
				return "set" + capital + oname.substring (5);
			} else
			if (oname.has_prefix ("get_")) {
				var capital = "%c".printf (oname[4].toupper ());
				return "get" + capital + oname.substring (5);
			}
		}
		switch (oname) {
			case "lock":
			case "base":
			case "clone":
			case "break":
			case "delete":
				name = "_"+oname;
				break;
			case "continue":
				name = "cont";
				break;
		}
		if (name != oname)
			warning ("Method %s renamed to %s (don't ask where)".printf (oname, name));
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
			int len = array_length(array);
			if (len < 0 )
				return element+"*"; // FIXME should this be element+"[]"?
			return element+"[%d]".printf (len); // FIXME will this work?
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
			/* Hack to bypass namespace rules in r2-bindings */
			case "SDBSdb":
				return "Sdb";
			case "gint":
			case "st32":
			case "int32":
			case "gint32":
				return "int";
			case "uint":
			case "guint":
			case "ut32":
			case "uint32":
			case "guint32":
				return "unsigned int";
			case "glong":
				return "long";
			case "ut8":
			case "uint8":
			case "guint8":
				return "unsigned char";
			case "guint16":
			case "uint16":
				return "unsigned short";
			case "st64":
			case "int64":
			case "gint64":
				return "long long";
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

	public override void visit_enum (Vala.Enum e) {
		add_includes (e);

		/*extends += "enum %s {\n".printf (e.name);
		foreach (var v in e.get_values ())
			extends += "\t%s = %s,\n".printf (v.name, CCodeBaseModule.get_ccode_name (v));
		extends += "};\n";*/
	}

	public override void visit_struct (Struct s) {
		add_includes (s);

		// FIXME does SWIG support actual namespaces?
		string name = s.get_full_name ().replace (ns_pfx, "").replace (".", "");
		string cname = CCodeBaseModule.get_ccode_name (s);

		structs += "typedef struct %s {\n".printf (cname);
		foreach (Field f in s.get_fields ())
			f.accept (this);
		structs += "} %s;\n".printf (name);

		var methods = s.get_methods ();
		if (methods.size > 0) {
			extends += "%%extend %s {\n".printf (name);

			// NOTE if m.accept (this) is used, it might try other functions than visit_method
			foreach (Method m in methods)
				visit_method (m);

			extends += "};\n";
		}
	}

	public override void visit_class (Class c) {
		add_includes (c);

		// FIXME does SWIG support actual namespaces?
		string name = c.get_full_name ().replace (ns_pfx, "").replace (".", "");
		string cname = CCodeBaseModule.get_ccode_name (c);

		structs += "typedef struct %s {\n".printf (cname);
		foreach (Field f in c.get_fields ())
			f.accept (this);
		structs += "} %s;\n".printf (name);

		foreach (Vala.Enum e in c.get_enums ())
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
			extends += "%%extend %s {\n".printf (name);

			if (freefun != null && freefun != "")
				extends += "\t~%s() {\n\t\t%s(self);\n\t}\n".printf (name, freefun);

			// NOTE if m.accept (this) is used, it might try other functions than visit_method
			foreach (Method m in methods)
				visit_method (m);

			extends += "};\n";
		}

		foreach (Struct s in c.get_structs ())
			s.accept (this);
		foreach (Class k in c.get_classes ())
			k.accept (this);
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
			int len = array_length(array);	
			if (len < 0)
				field = element + "* " + f.name; // FIXME should this be element+"[]"?
			field = element + " " + f.name + "[%d]".printf (len); // FIXME will this work?
		} else {
			/* HACK to support generics. this is r2 specific */
			string _type = type.to_string ();
			if (_type.index_of ("RListIter") != -1) {
				field = "RListIter* " + f.name;
			} else
			if (_type.index_of ("RList") != -1) {
				field = "RList* " + f.name;
			} else
				field = type_name (type) + " " + f.name;
		}

		structs += "\t" + field + ";\n";
	}

	public override void visit_method (Method m) {
		if (m.is_private_symbol ())
			return;

		add_includes (m);

		string cname = CCodeBaseModule.get_ccode_name (m), alias = get_alias (m.name);
		var parent = m.parent_symbol;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0, is_constructor = (m is CreationMethod);
		bool parent_is_class = parent is Class || parent is Struct;

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		string ret = type_name (m.return_type, true);

		string def_args = "", call_args = "";
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
				applys += "\t%%apply %s %s { %s %s };\n".printf (arg_type, var_name, arg_type, arg_name);
				clears += "\t%%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args = sep (call_args, ", ") + arg_name;
			def_args = sep (def_args, ", ") + arg_type + " " + arg_name;
		}

		if (is_constructor) {
			//externs += "extern %s* %s (%s);\n".printf (classcname, cname, def_args);
			var classname = parent.get_full_name ().replace (ns_pfx, "").replace (".", "");
			extends += applys;
			extends += "\t%s (%s) {\n".printf (classname, def_args);
			if (context.is_defined ("GOBJECT"))
				extends += "\t\tg_type_init ();\n";
			extends += "\t\treturn %s (%s);\n\t}\n".printf (cname, call_args);
			extends += clears;
		} else {
			string func = "";
			string fbdy = "";
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

			//BEGIN HACK HACK HACK DIE IN A FIRE
			if (cxx_mode && ret.index_of ("std::vector") != -1) {
				ret = ret.replace (">*", ">").replace ("*>",">");
				int ptr = ret.index_of ("<");
				string iter_type = (ptr==-1)?ret:ret[ptr:ret.length];
				iter_type = iter_type.replace ("<", "");
				iter_type = iter_type.replace (">", "");
				iter_type = iter_type.replace ("*", "");
				//ret = ret.replace ("*>", ">");
				// TODO: Check if iter type exists before failing
				//       instead of hardcoding the most common type '<G>'
				// TODO: Do not construct a generic class if not supported
				//       instead of failing.
				if (iter_type == "G*") /* No generic */
					error ("Oops. No <G> type support.\n");
				// TODO: Do not recheck the return_type
				if (m.return_type.to_string ().index_of ("RList") != -1) {
					fbdy += "\t\t%s ret;\n".printf (ret);
					fbdy += "\t\tRList *list;\n";
					fbdy += "\t\tRListIter *iter;\n";
					fbdy += "\t\t%s *item;\n".printf (iter_type);
					fbdy += "\t\tlist = %s (%s);\n".printf (cname, call_args);
					fbdy += "\t\tif (list)\n";
					fbdy += "\t\tfor (iter = list->head; iter && (item = (%s*)iter->data); iter = iter->n)\n".printf (iter_type);
					fbdy += "\t\t\tret.push_back(*item);\n";
					fbdy += "\t\treturn ret;\n";
					fbdy += "\t}\n";
				}
				vectors += "\t%%template(%sVector) std::vector<%s>;\n".printf (
						iter_type, iter_type);
			} else 
			//END HACK HACK HACK DIE IN A FIRE

			fbdy += "\t\t%s%s(%s);\n\t}\n".printf ((ret == "void")?"":"return ", cname, call_args);

			if (is_static)
				func += "\tstatic %s %s(%s) {\n".printf (ret, alias, def_args);
			else func += "\t%s %s(%s) {\n".printf (ret, alias, def_args);
			func += fbdy;
			func += clears;

			if (!parent_is_class) {
				statics += func;
				extends += "\tstatic %s %s(%s);\n".printf (ret, alias, def_args);
			} else
				extends += func;
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
			//foreach (Field f in ns.get_fields ())
			//	f.accept (this);
			foreach (Vala.Enum e in ns.get_enums ())
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

		if (cxx_mode && vectors != "")
			stream.printf ("%%include \"std_vector.i\"\n\nnamespace std {\n%s}\n", vectors);
		stream.printf ("%s\n", structs);
		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", extends);
	}
}

