/* Copyleft 2014 -- williballenthin */

using Vala;


public class GoWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	string classname = "";
	string classcname;
	string defs = "";
	string statics = "";
	string extends = "";
	string enums = "";
	string nspace;

	bool needs_unsafe = false;  // set to true if the 'unsafe' package needs to be imported because a void* pointer was encountered

	string _indent = ""; // TODO(wb): removeme
	void debug(string s) {
		notice(_indent + s);
	}
	void indent() {
		_indent = _indent + "  ";
	}
	void dedent() {
		_indent = _indent.substring(0, _indent.length - 2);
	}

	public GoWriter () {
	}

	public override string get_filename (string base_name) {
		return base_name+".go";
	}

	string get_alias (string name) {
		string nname;
		switch (name) {
		case "break":  // see: http://golang.org/ref/spec:/Identifiers
		case "while":
		case "for":
		case "if":
		case "case":
		case "continue":
		case "chan":
		case "const":
		case "default":
		case "defer":
		case "else":
		case "fallthrough":
		case "func":
		case "go":
		case "goto":
		case "interface":
		case "map":
		case "package":
		case "range":
		case "return":
		case "select":
		case "struct":
		case "switch":
		case "var":
			nname = "X" + name;
			break;
		case "type":
			nname = "_type";  // go specific hack for struct names, see http://golang.org/cmd/cgo:/"Go references to C"
			break;
		default:
			nname = name;
			break;
		}
		if (name != nname) {
			warning ("%s symbol renamed to %s".printf(name, nname));
		}
		return nname;
	}

	string get_ctype (string _type) {
		string type = _type;
		string? iter_type = null;
		if (type == "null")
			error ("Cannot resolve type");
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

		// TODO(wb): need to do this.
		switch (type) {
		case "G": /* generic type :: TODO: review */
		case "gconstpointer":
		case "gpointer":
		case "void*":
	 		return "void*";
		case "gsize":
			return "size_t";
		case "gdouble":
			return "double";
		case "gfloat":
			return "float";
		case "ut8":
		case "uint8":
		case "guint8":
			return "byte";
		case "gchar**":
			return "char **";
		case "char":
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
		case "const gchar*":
			return "string"; // XXX lost const?
		case "void":
			return "void";
		case "int[]":
		case "int":
		case "gint":
	 		return "int";
		case "guint":
	 		return "uint";
		case "glong":
	 		return "long";
		case "st64":
		case "int64":
		case "gint64":
			return "long";
		case "ut64":
		case "uint64":
		case "guint64":
			return "ulong";
		/* XXX swig does not support unsigned char* */
		case "uint8*":
		case "guint8*":
			return "byte*";
		case "guint16":
		case "uint16":
			return "ushort";
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
		default:
			break;
		}
		return type;
	}

	bool is_target_file (string path) {
		// FIXME implement the new method with use_namespace instead
		foreach (var file in source_files)
			if (file == path)
				return true;
		return false;
	}

	public override void visit_source_file (SourceFile source) {
		if (is_target_file (source.filename)) {
			/*
			foreach (var c in source.get_nodes()) {
				debug(c.to_string());
				indent();
				foreach (var at in c.attributes) {
					debug("name: %s".printf(at.name));
				}
				dedent();
			}
			*/
			source.accept_children (this);
		}
	}

	public void process_includes (Symbol s) {
		debug("process_includes(sym: %s)".printf(s.name));
		indent();
		foreach (var foo in CCodeBaseModule.get_ccode_header_filenames (s).split (",")) {
			debug("include(%s)".printf(foo));
			var include = true;
			foreach (var inc in includefiles) {
				if (inc == foo) {
					include = false;
					break;
				}
			}
			if (include) {
				debug("...adding it");
				includefiles.prepend (foo);
			}
		}
		dedent();
	}

	private string cleanup_underscores(string name) {
		if (name.length == 0) {
			return "";
		} else if (name.length == 1) {
			// accept trailing '_'
			return name;
		} else if (name.index_of("_") == -1) {
			return name;
		} else {  // there is a '_' here somewhere
			int i = name.index_of("_");
			if (i == name.length - 1) {
				// accept trailing '_'
				return name;
			}
			// there must be at least one more character

			// everything before the '_'
			string before = "";
			if (i != 0) {
				before = name.substring(0, i);
			}

			// find next non-'_' character uppercase, or all '_' if thats all thats left
			string next;
			int j = i + 1;
			while (true) {
				if (name[j] != '_') {
					next = name.substring(j, 1).up();
					break;
				}
				j++;
				if (j == name.length) {  // only '_' remain
					next = name.substring(i, j - i);  // so catch them all
					break;
				}
			}
			debug("next: %s".printf(next));

			if (j >= name.length - 2) {
				return before + next;
			} else {
				debug("else: %s".printf(name.substring(j + 1)));
				// do rest of string
				return before + next + cleanup_underscores(name.substring(j + 1));
			}
		}
	}

	// see tests t/go/camelcase.vapi
	private string camelcase(string name) {
		if (name.length == 0) {
			return "";
		} else if (name.length == 1) {
			return name.up();
		} else {
			return name.substring(0, 1).up() + cleanup_underscores(name.substring(1, name.length - 1));
		}
	}

	// given a DataType symbol, return a string that contains the Go source code for that type.
	private string get_go_type(DataType type) {
		if (type.to_string() == "G") {
			// TODO
			// error, dont support generics
			warning("We don't support generics");
			//return;
		}

		if (type.to_string().index_of ("<") != -1) {
			// TODO
			// error, dont support generics
			warning("We don't support generics (2)");
			//return;
		}

		string typename = get_ctype (type.to_string());
		typename = typename.replace("*", "").strip();  // we can typecheck to determine if this is a pointer, so throw away '*'
		string maybe_pointer_sym = "";  // if `type` is a pointer, then this will contain the appropriate '*'
		string maybe_array_sym = "";  // if `type` is an array, then this will contain the appropriate "[]"
		if (type is PointerType) {
			if (typename == "void") {
				typename = "unsafe.Pointer";  // go specific hack type for void *
				this.needs_unsafe = true;
				maybe_pointer_sym = "";
			} else {
				maybe_pointer_sym = "*";
			}
		}

		if (type is ArrayType) {
			maybe_array_sym = "[]";
		}

		return "%s%s%s".printf(maybe_array_sym, maybe_pointer_sym, typename);
	}

	private bool is_string(CodeNode t) {
		if (t is DataType) {
			DataType a = t as DataType;
			return a.to_string() == "string";
		} else if (t is Field) {
			Field a = t as Field;
			return a.variable_type.to_string() == "string";
		} else if (t is Vala.Parameter) {
			Vala.Parameter a = t as Vala.Parameter;
			return a.variable_type.to_string() == "string";
		} else {
			warning("unexpected type to is_string");
			return false;
		}
	}

	// here, we use explicit accessors and mutators to fixup accessibility.
	public void walk_field (string class_name, Field f, bool is_static=false) {
		debug("walk_field(name: %s)".printf(f.name));
		indent();

		// TODO(wb): handle visibility
		if (f.access != SymbolAccessibility.PUBLIC) {
			debug("private.");
			dedent();
			return;
		}

		string cname = CCodeBaseModule.get_ccode_name(f);
		string name = get_alias(cname);

		// TODO: handle generics. ATM, type of `public G data` becomes `func ... GetData() void`

		// TODO: make this a function `is_string`
		if (is_string(f)) {
			defs += "func (c %s) Get%s() %s {\n".printf(class_name, camelcase(f.name), get_go_type(f.variable_type));
			defs += "    return C.GoString(c.%s)\n".printf(name);
			defs += "}\n";

			defs += "func (c %s) Set%s(a %s) {\n".printf(class_name, camelcase(f.name), get_go_type(f.variable_type));
			defs += "    c.%s = C.CString(a)\n".printf(name);
			defs += "    return\n";
			defs += "}\n";
		} else {
			defs += "func (c %s) Get%s() %s {\n".printf(class_name, camelcase(f.name), get_go_type(f.variable_type));
			defs += "    return c.%s\n".printf(name);
			defs += "}\n";

			defs += "func (c %s) Set%s(a %s) {\n".printf(class_name, camelcase(f.name), get_go_type(f.variable_type));
			defs += "    c.%s = a\n".printf(name);
			defs += "    return\n";
			defs += "}\n";
		}


		dedent();
	}

	HashTable<string,bool> defined_classes = new HashTable<string,bool> (str_hash, str_equal);

	public void walk_struct (string pfx, Struct s) {
		debug("walk_struct(pfx: %s, name: %s)".printf(pfx, s.name));
		indent();

		defs += "type %s%s C.%s\n".printf(pfx, s.name, CCodeBaseModule.get_ccode_name(s));
		foreach (var f in s.get_fields()) {
			walk_field(s.name == null ? "" : s.name, f);
		}
		defs += "\n";

		dedent();
	}

	public void walk_enum (Vala.Enum e) {
		var pfx = CCodeBaseModule.get_ccode_prefix(e);
		debug("walk_enum(pfx: %s, name: %s)".printf(pfx, e.name));
		indent();

		enums += "const (\n";
		foreach (var v in e.get_values()) {
			debug("enum(name: %s)".printf(v.name));
			enums += "    %s%s = C.%s%s\n".printf(pfx, v.name, pfx, v.name);
		}
		enums += ")\n";
		enums += "type %s int".printf(e.name);

		dedent();
	}

	inline bool is_generic(string type) {
		return (type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	private string get_function_declaration_parameters(Method f) {
		string def_args = "";
		string pfx = "";

		bool first = true;
		foreach (var p in f.get_parameters ()) {
			string arg_name = p.name;
			DataType? arg_type = p.variable_type;
			if (arg_type == null) {
				warning("failed to resolve parameter type");
				continue;
			}

			if (first) {
				first = false;
			} else {
				pfx = ", ";
			}

			string maybe_pointer_sym = "";
			if (p.direction != ParameterDirection.IN) {
				// TODO: exploit multiple return values?
				if (p.direction == ParameterDirection.OUT) {
					if (! is_string(p)) {
						maybe_pointer_sym = "*";
					}
				} else if (p.direction == ParameterDirection.REF) {
					if (! is_string(p)) {
						maybe_pointer_sym = "*";
					}
				}
			}

			// TODO: consider special handling of `uint8  *buf, int len`?

			if (is_string(p)) {
				// what about array of char *?  I think we have to let the caller deal with it
				// hopefully overflows don't happen here?
				def_args += "%s%s %sstring".printf (pfx, arg_name, maybe_pointer_sym);
			} else {
				def_args += "%s%s %s%s".printf (pfx, arg_name, maybe_pointer_sym, get_go_type(arg_type));
			}
		}

		return def_args;
	}

	// the duplication here is annoying. theres really only about a one line difference
	private string get_function_call_parameters(Method f) {
		string call_args = "";
		string pfx = "";

		bool first = true;
		foreach (var p in f.get_parameters ()) {
			string arg_name = p.name;
			DataType? arg_type = p.variable_type;
			if (arg_type == null) {
				warning("failed to resolve parameter type");
				continue;
			}

			if (first) {
				first = false;
			} else {
				pfx = ", ";
			}

			string maybe_pointer_sym = "";
			if (p.direction != ParameterDirection.IN) {
				// TODO: exploit multiple return values?
				if (p.direction == ParameterDirection.OUT) {
					if (! is_string(p)) {
						maybe_pointer_sym = "*";
					}
				} else if (p.direction == ParameterDirection.REF) {
					if (! is_string(p)) {
						maybe_pointer_sym = "*";
					}
				}
			}

			// TODO: consider special handling of `uint8  *buf, int len`?

			if (is_string(p)) {
				// what about array of char *?  I think we have to let the caller deal with it
				// hopefully overflows don't happen here?
				call_args += "%sC.CString(%s)".printf (pfx, arg_name);
			} else {
				call_args += "%s%s".printf (pfx, arg_name);
			}
		}

		return call_args;
	}

	private string get_function_declaration_return_value(Method f) {
		var ret = f.return_type.to_string ();
		// TODO: generics
		ret = get_ctype (is_generic (ret)?  ret : CCodeBaseModule.get_ccode_name (f.return_type));
		if (ret == null) {
			error ("Cannot resolve return type (3)\n");
			return "";
		}
		var void_return = (ret == "void");

		if ( ! void_return) {
			return get_go_type(f.return_type);
		} else {
			return "";
		}
	}

	// see tests t/go/namespace_functions.vapi
	public void walk_function(string nsname, Method f) {
		string cname = CCodeBaseModule.get_ccode_name(f);
		debug("walk_function(ns: %s, name: %s)".printf(nsname, cname));
		indent();

		string ret;
		bool void_return;
		if ((f.binding & MemberBinding.STATIC) == 0) {
			warning("non-static method where function expected");
		}
		if (f is CreationMethod) {
			warning("constructor where function expected");
		}
		if (f.is_private_symbol ()) {
			debug("private.");
			dedent();
			return;
		}

		ret = f.return_type.to_string ();
		// TODO: generics
		ret = get_ctype (is_generic (ret)?  ret : CCodeBaseModule.get_ccode_name (f.return_type));
		if (ret == null) {
			error ("Cannot resolve return type for %s\n".printf (cname));
		}
		void_return = (ret == "void");

		string def_args = get_function_declaration_parameters(f);
		string call_args = get_function_call_parameters(f);
		if ( ! void_return) {
			defs += "func (_ %s) %s(%s) %s {\n".printf (nsname, camelcase(f.name), def_args, get_go_type(f.return_type));
			if (is_string(f.return_type)) {
				// we have to let the caller deal with array of char *
				// what happens if there are embedded nulls?
				defs += "    return C.GoString(%s(%s))\n".printf (cname, call_args);
			} else {
				// what about void*?
				defs += "    return %s(%s)\n".printf (cname, call_args);
			}
		} else {
			defs += "func (_ %s) %s(%s) {\n".printf (nsname, camelcase(f.name), def_args);
			defs += "    %s(%s)\n".printf (cname, call_args);
		}
		defs += "}\n";

		dedent();
	}

	public void walk_method (string classname, Method m) {
		string cname = CCodeBaseModule.get_ccode_name(m);
		debug("walk_method(ns: %s, name: %s)".printf(classname, cname));
		indent();

		// TODO: "unowned"/static methods
		string ret;
		bool void_return;
		if ((m.binding & MemberBinding.STATIC) == 0) {
			warning("non-static method where function expected");
		}
		if (m is CreationMethod) {
			warning("constructor where function expected");
		}
		if (m.is_private_symbol ()) {
			debug("private.");
			dedent();
			return;
		}

		ret = m.return_type.to_string ();
		// TODO: generics
		ret = get_ctype (is_generic (ret)?  ret : CCodeBaseModule.get_ccode_name (m.return_type));
		if (ret == null) {
			error ("Cannot resolve return type for %s\n".printf (cname));
		}
		void_return = (ret == "void");

		string def_args = get_function_declaration_parameters(m);
		string call_args = get_function_call_parameters(m);

		defs += "func (this *%s) %s(".printf(classname, camelcase(m.name));
		if (def_args != "") {
			defs += "%s".printf(def_args);
		}
		defs += ") ";
		if ( ! void_return) {
			defs += "%s ".printf(get_go_type(m.return_type));
		}
		defs += "{\n";
		defs += "    ";
		if ( ! void_return) {
			defs += "return ";
			if (is_string(m.return_type)) {
				// TODO: use wrap_type function
				defs += "C.GoString(";
			}

			defs += "%s(this".printf(cname);
			if (call_args != "") {
				defs += ", %s".printf(call_args);
			}
			defs += ")";

			if (is_string(m.return_type)) {
				defs += ")";
			}
			defs += "\n";
		} else {
			defs += "%s(this".printf(cname);
			if (call_args != "") {
				defs += ", %s".printf(call_args);
			}
			defs += ")\n";
		}
		defs += "}\n";

		dedent();
	}

	public void walk_constructor(string classname, Method m, string free_function) {
		string cname = CCodeBaseModule.get_ccode_name(m);
		debug("walk_method(ns: %s, name: %s)".printf(classname, cname));
		indent();

		// TODO: "unowned"/static methods
		string ret;
		bool void_return;
		if ((m.binding & MemberBinding.STATIC) == 0) {
			warning("non-static method where function expected");
		}
		if (m is CreationMethod) {
			warning("constructor where function expected");
		}
		if (m.is_private_symbol ()) {
			debug("private.");
			dedent();
			return;
		}

		ret = m.return_type.to_string ();
		// TODO: generics
		ret = get_ctype (is_generic (ret)?  ret : CCodeBaseModule.get_ccode_name (m.return_type));
		if (ret == null) {
			error ("Cannot resolve return type for %s\n".printf (cname));
		}
		void_return = (ret == "void");

		string def_args = get_function_declaration_parameters(m);
		string call_args = get_function_call_parameters(m);

		string postfix = "";
		if (m.name != ".new") {
			postfix = camelcase(m.name);
		}
		defs += "func New%s%s(".printf(classname, postfix);
		if (def_args != "") {
			defs += "%s".printf(def_args);
		}
		defs += ") *%s {\n".printf(classname);

		defs += "    var ret *%s\n".printf(classname);
		defs += "    ret = C.%s(".printf(CCodeBaseModule.get_ccode_name(m));
		if (call_args != "") {
			defs += "%s".printf(call_args);
		}
		defs += ")\n";
		if (free_function != "") {
			defs += "    var finalizer = func(r *%s) {\n".printf(classname);
			defs += "        C.%s(r)\n".printf(free_function);
			defs += "    }\n";
			defs += "    SetFinalizer(ret, finalizer)\n";
		}
		defs += "    return ret\n";
		defs += "}\n";

		dedent();
	}

	public void walk_class (string pfx, Class c) {
		debug("walk_class(pfx: %s, name: %s)".printf(pfx, c.name));
		indent();
		foreach (var k in c.get_structs ()) {
			walk_struct (c.name, k);
		}
		foreach (var k in c.get_classes ()) {
			walk_class (c.name, k);
		}
		classname = pfx+c.name;
		classcname = CCodeBaseModule.get_ccode_name (c);

		process_includes (c);
		if (defined_classes.lookup (classname)) {
			debug("already defined");
			dedent();
			return;
		}
		defined_classes.insert (classname, true);

		bool has_constructor = false;
		foreach (var m in c.get_methods ()) {
			if (m is CreationMethod) {
				has_constructor = true;
				break;
			}
		}
		bool has_destructor = !c.is_compact;

		defs += "type %s C.%s\n".printf(classname, classcname);
		foreach (var f in c.get_fields()) {
			walk_field(classname, f);
		}

		foreach (var e in c.get_enums ()) {
			walk_enum (e);
		}

		if (has_destructor && has_constructor) {
			if (CCodeBaseModule.is_reference_counting (c)) {
				string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
				if (freefun != null && freefun != "") {
					// TODO: add finalizer
				}
			} else {
				string? freefun = CCodeBaseModule.get_ccode_free_function (c);
				if (freefun != null) {
					// TODO: add finalizer
				}
			}
		}

		foreach (var m in c.get_methods ()) {
			if ( ! (m is CreationMethod)) {
				walk_method (classname, m);
			} else {
				string free_function = "";
				if (CCodeBaseModule.is_reference_counting (c)) {
					string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
					if (freefun != null && freefun != "") {
						free_function = freefun;
					}
				} else {
					string? freefun = CCodeBaseModule.get_ccode_free_function (c);
					if (freefun != null) {
						free_function = freefun;
					}
				}
				walk_constructor(classname, m, free_function);
			}
		}

		defs += "\n";
		dedent();
	}


	// go doesn't really support namespaces. Often code is namespaced by
	//  directory hierarchy, but thats for code organization.
	// we eat namespaces here, as they don't generate anything besides their children.
	public override void visit_namespace (Namespace ns) {
		debug("walk_namespace(name: %s)".printf(ns.name));
		indent();
		if (ns.name == "")
			return;

		classname = "";
		SourceReference? sr = ns.source_reference;
		if (sr == null || !is_target_file (sr.file.filename)) {  // TODO: should this be &&?
			dedent();
			return;
		}

		nspace = ns.name;
		process_includes (ns);
		foreach (var e in ns.get_enums ()) {
			// enums will float to the top-level "namespace" in Go, since we aren't doing namespaces.
			walk_enum (e);
		}
		foreach (var c in ns.get_structs()) {
			walk_struct(ns.name == modulename ? ns.name : "", c);
		}
		if (ns.get_methods().size + ns.get_fields().size > 0) {
			// Go only does namespacing through file system paths, whish is probably not appropriate/feasible here
			//  so we fake it by creating a new type, and one instance of it,
			//  and attach the functions to it.
			// Note, this doesn't work for nested namespaces, but its better than nothing.
			//
			// for example:
			//   namespace N { public static void fn1(); }
			//
			// becomes:
			//   type nsimptN int
			//   func (_ nsimpN) Fn1() { fn1() }
			//   var N nsimpN
			//
			// so a user can do:
			//   import "/some/path/test"
			//   test.N.Fn()
			string fake_ns_name = "nsimp%s".printf(ns.name);
			defs += "type %s int\n".printf(fake_ns_name);
			foreach (var c in ns.get_fields()) {
				walk_field(fake_ns_name, c);
			}
			foreach (var m in ns.get_methods()) {
				walk_function(fake_ns_name, m);
			}
			defs += "var %s %s\n".printf(ns.name, fake_ns_name);
			defs += "\n";
		}
		var classprefix = ns.name == modulename? ns.name: "";
		foreach (var c in ns.get_classes ()) {
			walk_class (classprefix, c); //ns.name, c);
		}

		dedent();
	}

	public override void write (string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (file));

		// before the `pre` stuff because we need `includefiles` to be populated.
		context.accept (this);

		var pre  = "package %s\n".printf(modulename);
		pre += "\n";
		pre += "// #cgo LDFLAGS: -l%s\n".printf(modulename);  // TODO(wb): how2get library name?
		foreach (var inc in includefiles) {
			pre += "// #include \"%s\"\n".printf(inc);
		}
		pre += "import \"C\"\n";
		if (this.needs_unsafe) {
			pre += "import \"unsafe\"\n";
		}

		stream.printf ("/* valabind autogenerated Go bindings for %s */\n".printf (modulename));
		stream.printf ("%s\n", pre);
		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", defs);
		stream.printf ("%s\n", extends);
	}
}

