/* Copyright GPLv3 - 2009-2014 - pancake */

using Vala;

private class CtypeCompiler {
	public GLib.SList<CtypeClass> classes;
	public CtypeClass cur;
	GLib.SList<CtypeClass> n;
	private bool sorted = false;

	public string to_string () {
		var str = "";
		if (!this.sorted)
			this.sort ();
		foreach (var c in this.classes)
			str += c.to_string ();
		return str;
	}

	public CtypeCompiler() {
		this.cur = null;
	}

	public bool contains (string c) {
		foreach (var a in n)
			if (a.name == c)
				return true;
		return false;
	}

	public void sort () {
		uint count, count2 = 0;
		n = new GLib.SList<CtypeClass>();
		do {
			count = classes.length ();
			foreach (var c in classes) {
				if (c.is_satisfied (this)) {
					n.append (c);
					classes.remove (c);
				} else {
					warning ("UNSATISFIED "+c.name);
				}
			}
			count2 = classes.length ();
			if (count2>0 && count == count2) // detect infinite loop
				error ("Cannot compile\n");
		} while (count2>0);
		/* refill */
		foreach (var c in classes) {
			if (c.is_satisfied (this)) {
				n.prepend (c);
				classes.remove (c);
			}
		}
		this.classes = n.copy ();
		this.sorted = true;
	}

	public void add_class (string name, string text) {
		var cc = new CtypeClass (name);
		this.classes.append (cc);
		this.cur = cc;
		this.cur.append (text);
		this.sorted = false;
	}
}

private class CtypeClass {
	public string name;
	public string text;
	public GLib.SList<string> deps;

	public bool is_satisfied (CtypeCompiler c) {
		foreach (var d in deps) {
			if (d == this.name) {
				stderr.printf ("==> "+d+"\n");
		//		break;
			}
			stderr.printf ("--> "+d+"\n");
			if (!c.contains (d))
				return false;
		}
		stderr.printf ("    *** Yep. "+name+" is satisfied\n");
		return true;
	}

	public CtypeClass(string? name) {
		this.deps = new SList<string>();
		this.name = name;
		this.text = "";
	}

	public bool contains(SList<string> a, string b) {
		if (b == this.name) {
			error ("Classes with self dependencies are not supported");
		//	return true;
		}
		foreach (var i in a) {
			if (i == b)
				return true;
		}
		return false;
	}

	public void add_dependency (string d) {
		if (!this.contains (deps, d))
			deps.append (d);
	}

	public bool depends_on(string d) {
		foreach (var s in deps)
			if (s == d)
				return true;
		return false;
	}

	public string to_string() {
		return this.text;
	}

	public void append(string s) {
		this.text += s;
	}
}

public class CtypesWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	CtypeCompiler ctc = new CtypeCompiler ();
	string ?ns_pfx;
	string delegatestr = "";

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
			case "import":
			case "from":
			case "del":
				name = "_"+oname;
				break;
			case "continue":
				name = "cont";
				break;
		}
		if (name != oname)
			warning ("Method %s renamed to %s".printf (oname, name));
		return name;
	}

	string type_name (DataType type, bool retType=false, bool ignoreRef=false) {
		if (type == null) {
			warning ("Cannot resolve type");
			return "__UNRESOLVED_TYPE_OH_PLEASE_KILL_ME__";
		}

		// HACK is this required?
		if (type is EnumValueType)
			return "c_long";

		// HACK needs proper generic support
		if (type is GenericType)
			return "c_void_p";
			//return type.to_qualified_string ();

		if (type is PointerType) {
			var tn = type_name ((type as PointerType).base_type, retType, true);
			if (tn == "void")
				return "c_void_p";
			return "POINTER("+tn+")";
		}

		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type, retType);
			if (!array.fixed_length)
				return element; //+"*"; // FIXME should this be element+"[]"?
			return "'"+element+"', * %d".printf (array.length); // FIXME will this work?
		}

		if (!ignoreRef && (type is ReferenceType)) {
			string unref_type = type_name (type, retType, true);
			// HACK just check for the string class instead (how?)
			if (unref_type == "char*" || unref_type == "const char*")
				return unref_type;
			// FIXME should it be & under C++?
			return unref_type; //+"_p"; //+"*";
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
			case "char":
			case "gchar":
				return "c_char";
			case "gint":
				return "c_int";
			case "uint":
			case "guint":
				return "c_uint";
			case "glong":
				return "c_long";
			case "ut8":
			case "uint8":
			case "guint8":
				return "c_ubyte";
			case "guint16":
			case "uint16":
				return "c_ushort";
			case "gint16":
			case "int16":
			case "short":
				return "c_short";
			case "int":
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
				return "c_char_p";
			//case "const gchar*":
			//	return "const char*";
			// HACK needs proper generic support
			case "RList":
				return "RList";
		}
		return _type;
	}

	public override void visit_constant (Constant c) {
		warning ("Constants not yet supported on ctypes ("+c.name+")");
		//var cname = CCodeBaseModule.get_ccode_name (c);
		//classes += c.name+" = "+cname+";\n";
	}

	public override void visit_enum (Vala.Enum e) {
		add_includes (e);
		// TODO: copy from node
	}

	public override void visit_struct (Struct s) {
		string name = s.get_full_name ().replace (ns_pfx, "").replace (".", "");
		visit_struct_or_class (s, name, s.get_fields (), s.get_methods (), null);
	}

	public override void visit_class (Class c) {
		string name = c.get_full_name ().replace (ns_pfx, "").replace (".", "");
		visit_struct_or_class (c, name, c.get_fields (), c.get_methods (), c.get_delegates ());

		/* walk nested structs and classes */
		foreach (Struct s in c.get_structs ())
			s.accept (this);
		foreach (Class k in c.get_classes ())
			k.accept (this);
		/* TODO: add support for freefun in destructor 
		string? freefun = null;
		if (CCodeBaseModule.is_reference_counting (c))
			freefun = CCodeBaseModule.get_ccode_unref_function (c);
		else
			freefun = CCodeBaseModule.get_ccode_free_function (c);
		if (freefun == "")
			freefun = null;
		var methods = c.get_methods ();
		if (freefun != null || methods.size > 0) { ...  */
	}

	private string get_constructor_args(Vala.List<Method> methods) {
		foreach (Method m in methods) {
			if (m is CreationMethod) {
				var str = "";
				add_includes (m);
				foreach (var foo in m.get_parameters ()) {
					str += ", "+get_alias (foo.name);
				}
				return str;
			}
		}
		return "";
	}

	string wrappers;
int n = 0;

	private void visit_struct_or_class (Symbol s, string name,
			Vala.List<Field> fields, Vala.List<Method> methods,
			Vala.List<Delegate>? delegates) {
		//string cname = CCodeBaseModule.get_ccode_name (s);
		add_includes (s);
		ctc.add_class (name, "class "+name+"(Structure): #"+n.to_string()+"\n");
stderr.printf ("--> "+name+" ("+n.to_string()+")\n");
n++;
		if (fields.size > 0) {
			ctc.cur.append ("\t_fields_ = [\n");
			foreach (Field f in fields)
				f.accept (this);
			ctc.cur.append ("\t]\n");
		} else {
			ctc.cur.append ("\t_fields_ = [\n\t]\n");
		}
		if (methods.size > 0) {
			string call_args = get_constructor_args (methods);
			ctc.cur.append ("\tdef __init__(self"+call_args+"):\n");
			ctc.cur.append ("\t\tStructure.__init__(self)\n");
			// TODO: control how many methods and constructors there are
			// TODO: add support for more than one constructor
			/* constructors */
			wrappers = "";
			foreach (Method m in methods)
				if (m is CreationMethod)
					visit_method (m);
			/* helper function */
			if (name == "RList")
				ctc.cur.append (
					"\tdef to_list(self,type):\n"+
					"\t\treturn rlist2array(self,type)\n");
			/* delegates */
			if (delegates != null)
				foreach (Delegate d in delegates)
					visit_delegate (d);

			ctc.cur.append ("\n\t_o = AddressHolder()\n\n");

			/* methods */
			foreach (Method m in methods)
				if (!(m is CreationMethod))
					visit_method (m);
			ctc.cur.append (wrappers);
			ctc.cur.append ("\n");
		}
	}

	public override void visit_field (Field f) {
		if (f.is_private_symbol ())
			return;
		// HACK don't output fields with C++ keywords as names.
		if (f.name == "class")
			return;
		string field = "";
		DataType type = f.variable_type;
		var stype = type.to_string ();
		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type);
			warning ("Arrays not yet supported in ctypes bindings");
			if (!array.fixed_length)
				field = element + "* " + f.name; // FIXME should this be element+"[]"?
			field = "'%s', %s * %d".printf (f.name, element, array.length);
            stype = element;
		} else {
			/* HACK to support generics. this is r2 specific */
			if (stype.index_of ("RListIter") != -1) {
				stype = "c_void_p"; // XXX RListIter*";
			} else
			if (stype.index_of ("RList") != -1) {
				stype = "c_void_p"; // XXX "RList*";
			} else stype = type_name (type);
			field = "\"%s\", %s".printf (f.name, stype);
		}
		ctc.cur.append ("\t\t(" + field + "),\n");
		if (stype[0].isupper () && 
				!stype.has_prefix ("POINTER") &&
				stype.index_of (".") == -1) {
//stderr.printf ("ADD DEP : "+field+"  "+stype+"\n");
			ctc.cur.add_dependency (stype);
		}
	}

	public override void visit_delegate (Delegate d) {
		string cname = CCodeBaseModule.get_ccode_name (d);

		string args = "";
		foreach (var p in d.get_parameters ()) {
			DataType? bar = p.variable_type;
			string? arg_type = type_name (bar);
			args += ", "+arg_type;
		}
		var cn = d.parent_symbol.get_full_name ().replace (ns_pfx, "").replace (".", "");
		this.delegatestr += cname + " = CFUNCTYPE ("+cn+args+")\n";
	}

	public override void visit_method (Method m) {
		if (m.is_private_symbol ())
			return;
		add_includes (m);

		string cname = CCodeBaseModule.get_ccode_name (m);
		//string alias = get_alias (m.name);
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);
		//var parent = m.parent_symbol;
		//bool parent_is_class = parent is Class || parent is Struct;
		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		string ret = type_name (m.return_type, true);
		string pyc_args = "";
		string def_args = "";
		string call_args = "";
		string clears = "";


		foreach (var foo in m.get_parameters ()) {
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null) {
				warning ("Unknown datatype "+foo.name+"\n");
				continue;
			}
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
					arg_type = "POINTER("+arg_type+")";
				//applys += "\t%%apply %s %s { %s %s };\n".printf (arg_type, var_name, arg_type, arg_name);
				clears += "\t%%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args = sep (call_args, ", ") + arg_name;
			def_args = sep (def_args, ", ") + arg_type + " " + arg_name;
			pyc_args = sep (pyc_args, ", ") + arg_type;
		}

		if (is_constructor) {
			var text = "\t\t%s = lib.%s\n".printf (cname, cname);
			text += "\t\t%s.restype = c_void_p\n".printf (cname);
			text += "\t\tself._o = %s (%s)\n".printf (cname, call_args); // TODO: support constructor arguments
#if 0
			var classname = parent.get_full_name ().replace (ns_pfx, "").replace (".", "");
			text += "\t%s (%s) {\n".printf (classname, def_args);
			if (context.is_defined ("GOBJECT"))
				text += "\t\tg_type_init ();\n";
			text += "\t\treturn %s (%s);\n\t}\n".printf (cname, call_args);
#endif
			text += clears;
			ctc.cur.append (text);
		} else {
			if (!is_static) {
				if (pyc_args == "")
					pyc_args = "c_void_p";
				else pyc_args = "c_void_p, " + pyc_args;
			}
			if (ret == "RList") {
				wrappers +="\tdef %s(self%s):\n".printf (m.name, call_args);
				m.name = "_"+m.name;
				string gen = "";
				var type = m.return_type;
				foreach (DataType t in type.get_type_arguments ())
					gen = sep (gen, ", ") + type_name (t);
				ret = "RList<"+gen+">";
				wrappers +="\t\treturn rlist2array(self.%s(%s),%s)\n".printf (
						m.name, call_args, gen);
			}
			ret = (ret=="void")? "None": "'"+ret+"'";
			ctc.cur.append (
				"\t%s, %s = register('%s','%s',%s)\n".printf (
				get_alias(m.name), cname, cname, pyc_args, ret));
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
		stream.printf (
			"# this file has been automatically generated by valabind\n"+
			"from ctypes import *\n"+
			"from ctypes.util import find_library\n"+
			"lib = CDLL (find_library ('%s'))\n", library);
		stream.puts (
			"def rlist2array(x,y):\n"+
			"	it = x.iterator ()\n"+
			"	ret = []\n"+
			"	while True:\n"+
			"		data = it.get_data ()\n"+
			"		ds = cast (data, POINTER(y)).contents\n"+
			"		ret.append (ds)\n"+
			"		if it.n == None:\n"+
			"			break\n"+
			"		it = it.get_next ()\n"+
			"	return ret\n"+
			"\n"+
			"class AddressHolder(object):\n"+
			"	def __get__(self, obj, type_):\n"+
			"		if getattr(obj, '_address', None) is None:\n"+
			"			obj._address = addressof(obj)\n"+
			"		return obj._address\n"+
			"\n"+
			"	def __set__(self, obj, value):\n"+
			"		obj._address = value\n"+
			"\n"+
			"class WrappedRMethod(object):\n"+
			"	def __init__(self, cname, args, ret):\n"+
			"		self.cname = cname\n"+
			"		self.args = args\n"+
			"		self.ret = ret\n"+
			"		self.args_set = False\n"+
			"		self.method = getattr(lib, cname)\n"+
			"\n"+
			"	def __call__(self, *a):\n"+
			"		if not self.args_set:\n"+
			"			if self.args:\n"+
			"				self.method.argtypes = [eval(x.strip()) for x in self.args.split(',')]\n"+
			"			self.method.restype = eval(self.ret) if self.ret else None\n"+
			"			self.args_set = True\n"+
			"		return self.method(*a)\n"+
			"\n"+
			"class WrappedApiMethod(object):\n"+
			"	def __init__(self, method, ret2, last):\n"+
			"		self.method = method\n"+
			"		self._o = None\n"+
			"		self.ret2 = ret2\n"+
			"		self.last = last\n"+
			"\n"+
			"	def __call__(self, *a):\n"+
			"		result = self.method(self._o, *a)\n"+
			"		if self.ret2:\n"+
			"			result = eval(self.ret2)(result)\n"+
			"		if self.last:\n"+
			"			return getattr(result, self.last)\n"+
			"		return result\n"+
			"\n"+
			"	def __get__(self, obj, type_):\n"+
			"		self._o = obj._o\n"+
			"		return self\n"+
			"\n"+
			"def register(cname, args, ret):\n"+
			"	ret2 = last = None\n"+
			"	if ret:\n"+
			"		if ret[0]>='A' and ret[0]<='Z':\n"+
			"			x = ret.find('<')\n"+
			"			if x != -1:\n"+
			"				ret = ret[0:x]\n"+
			"			last = 'contents'\n"+
			"			ret = 'POINTER('+ret+')'\n"+
			"		else:\n"+
			"			last = 'value'\n"+
			"			ret2 = ret\n"+
			"			\n"+
			"	method = WrappedRMethod(cname, args, ret)\n"+
			"	wrapped_method = WrappedApiMethod(method, ret2, last)\n"+
			"	return wrapped_method, method\n\n");
		context.root.accept (this);
		stream.printf (ctc.to_string ());
		stream.puts (delegatestr);
	}
}
