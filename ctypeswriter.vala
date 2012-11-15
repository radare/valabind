/* Copyleft 2009-2012 -- pancake, eddyb */

using Vala;

public class CtypesWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	string statics = "";
	string classes = "";
	string ?ns_pfx;

	public CtypesWriter () {
	}

	public override string get_filename (string base_name) {
		return base_name+".py";
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
				return "c_bool";
			case "gconstpointer":
			case "gpointer":
				return "c_void_p";
			case "gchar":
				return "c_char";
			case "gint":
				return "c_int";
			case "guint":
				return "c_uint";
			case "glong":
				return "c_long";
			case "ut8":
			case "uint8":
			case "guint8":
				return "c_uchar";
			case "guint16":
			case "uint16":
				return "c_ushort";
			case "st32":
			case "int32":
			case "gint32":
				return "c_int";
			case "ut32":
			case "uint32":
			case "guint32":
				return "c_uint";
			case "st64":
			case "int64":
			case "gint64":
				return "c_longlong";
			case "ut64":
			case "uint64":
			case "guint64":
				// HACK uint64_t doesn't work here because radare2 doesn't use the right type
				return "c_ulonglong";
			case "gdouble":
				return "c_double";
			case "gfloat":
				return "c_float";
			case "string":
				return retType ? "const char*" : "c_char_p";
			//case "const gchar*":
			//	return "const char*";
			// HACK needs proper generic support
			case "RList":
				warning ("RList is not yet supported for ctypes");
				if (generic != "")
					return "std::vector<"+generic+">";
				break;
		}
		return _type;
	}

	public override void visit_constant (Constant c) {
		var cname = CCodeBaseModule.get_ccode_name (c);
		classes += "%immutable "+c.name+";\n";
		classes += "static const char *"+c.name+" = "+cname+";\n";
	}

	public override void visit_enum (Vala.Enum e) {
		add_includes (e);
		// TODO: copy from node
	}

	public override void visit_struct (Struct s) {
		add_includes (s);

		// FIXME does SWIG support actual namespaces?
		string name = s.get_full_name ().replace (ns_pfx, "").replace (".", "");
		string cname = CCodeBaseModule.get_ccode_name (s);

		classes += "typedef struct %s {\n".printf (cname);
		foreach (Field f in s.get_fields ())
			f.accept (this);
		classes += "} %s;\n".printf (name);

		var methods = s.get_methods ();
		if (methods.size > 0) {
			classes += "%%extend %s {\n".printf (name);

			// NOTE if m.accept (this) is used, it might try other functions than visit_method
			foreach (Method m in methods)
				visit_method (m);

			classes += "};\n";
		}
	}

	public override void visit_class (Class c) {
		add_includes (c);

		string name = c.get_full_name ().replace (ns_pfx, "").replace (".", "");
		//string cname = CCodeBaseModule.get_ccode_name (c);

		classes += "class %s(Structure):\n".printf (name);
		classes += "	_fields_ = [\n";
		foreach (Field f in c.get_fields ())
			f.accept (this);
		classes += "	]\n";

/*
TODO: enum not yet supported
		foreach (Vala.Enum e in c.get_enums ())
			e.accept (this);
*/

		string? freefun = null;
		if (CCodeBaseModule.is_reference_counting (c))
			freefun = CCodeBaseModule.get_ccode_unref_function (c);
		else
			freefun = CCodeBaseModule.get_ccode_free_function (c);
		if (freefun == "")
			freefun = null;
		var methods = c.get_methods ();
		if (freefun != null || methods.size > 0) {
			classes += "	def __init__(self):\n";
			classes += "		# %s_new = getattr(lib,'%s')\n".printf (name, name);
			classes += "		# %s_new.restype = c_void_p\n";
			classes += "		# self._o = r_asm_new ()\n";

			// TODO: implement __del__
			//if (freefun != null && freefun != "")
			//	classes += "\t~%s() {\n\t\t%s(self);\n\t}\n".printf (name, freefun);

			// NOTE if m.accept (this) is used, it might try other functions than visit_method
			foreach (Method m in methods)
				visit_method (m);
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
			warning ("Arrays not yet supported in ctypes bindings");
			if (!array.fixed_length)
				field = element + "* " + f.name; // FIXME should this be element+"[]"?
			field = element + " " + f.name + "[%d]".printf (array.length); // FIXME will this work?
		} else {
			/* HACK to support generics. this is r2 specific */
			string _type = type.to_string ();
			if (_type.index_of ("RListIter") != -1) {
				_type = "RListIter*";
			} else
			if (_type.index_of ("RList") != -1) {
				_type = "RList*";
			} else _type = type_name (type);
			field = "\"%s\", %s".printf (f.name, _type);
		}
		classes += "\t\t(" + field + "),\n";
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
			classes += applys;
			classes += "\t%s (%s) {\n".printf (classname, def_args);
			if (context.is_defined ("GOBJECT"))
				classes += "\t\tg_type_init ();\n";
			classes += "\t\treturn %s (%s);\n\t}\n".printf (cname, call_args);
			classes += clears;
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

			fbdy += "\t\t%s%s(%s);\n\t}\n".printf ((ret == "void")?"":"return ", cname, call_args);

			if (is_static)
				func += "\tstatic %s %s(%s) {\n".printf (ret, alias, def_args);
			else func += "\t%s %s(%s) {\n".printf (ret, alias, def_args);
			func += fbdy;
			func += clears;

			// XXX above stuff must be removed CLEAR FUNC //
			string args = "c_void_p, c_bool";
			func = "\t\tregister(self,'%s','%s',%s)\n".printf (m.name, cname, args);

			if (!parent_is_class) {
				statics += func;
				classes += "\tstatic %s %s(%s);\n".printf (ret, alias, def_args);
			} else
				classes += func;
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
			foreach (Vala.Enum e in ns.get_enums ())
				e.accept (this);
			foreach (Struct s in ns.get_structs ())
				s.accept (this);
			foreach (Class c in ns.get_classes ())
				c.accept (this);
		}
		if (use)
			ns_pfx = null;
	}

	public override void write (string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (file));
		stream.printf ("from ctypes import *\n"+
			"from ctypes.util import find_library\n"+
			"lib = CDLL (find_library ('%s'))\n", modulename);
		stream.puts (
			"def register (self, name, cname, args, ret):\n"+
			"	g = globals ()\n"+
			"	g['self'] = self\n"+
			"	if (ret!='' and ret[0]>='A' and ret[0]<='Z'):\n"+
			"		last = '.contents'\n"+
			"		ret = \"POINTER(\"+ret+\")\"\n"+
			"		ret2 = ''\n"+
			"	else:\n"+
			"		last = ''\n"+
			"		ret2 = ret\n"+
			"	setattr (self,cname, getattr (lib, cname))\n"+
			"	exec ('self.%s.argtypes = [%s]'%(cname, args))\n"+
			"	if ret != '':\n"+
			"		exec ('self.%s.restype = %s'%(cname, ret), g)\n"+
			"		exec ('self.%s = lambda x: %s(self.%s(self._o, x))%s'%\n"+
			"			(name, ret2, cname, last),g)\n");
		context.root.accept (this);
		stream.printf ("%s\n", classes);
	}
}
