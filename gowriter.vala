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
	string vectors = "";
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


	// what we need is a method `find_namespace_roots` because
	//  i can't seem to figure out how to access them from the source_file.
	// namespaces don't appear to have parent links.
	// so maybe do an `accept_namespaces` and use this to build a
	//  a tree (because you can traverse down).
	// need to be careful of checking values of namespaces/instances/names.

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
				// recurse over everything afterwards
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
		if (type.to_string()== "G") {
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
		// TODO: C-string conversions

		if (get_go_type(f.variable_type) == "string") {
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

		dedent();
	}

	inline bool is_generic(string type) {
		return (type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	// see tests t/go/namespace_functions.vapi
	public void walk_function(string nsname, Method f) {
		string cname = CCodeBaseModule.get_ccode_name(f);
		debug("walk_function(ns: %s, name: %s)".printf(nsname, cname));
		indent();


		string alias = get_alias (f.name);
		string ret;
		string def_args = "";
		string cdef_args = "";
		string call_args = "";
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

		string pfx = "";
		string cpfx = "";

		bool first = true;
		foreach (var p in f.get_parameters ()) {
			string arg_name = p.name;
			DataType? arg_type = p.variable_type;
			if (arg_type == null) {
				warning("failed to resolve parameter type");
				continue;
			}
			string? type_name = get_ctype (CCodeBaseModule.get_ccode_name (arg_type));

			if (first) {
				first = false;
			} else {
				cpfx = ", ";
				pfx = ", ";
			}

			string maybe_pointer_sym = "";
			if (p.direction != ParameterDirection.IN) {
				// TODO: exploit multiple return values?
				var var_name = "";
				if (p.direction == ParameterDirection.OUT) {
					if (type_name != "string") {
						maybe_pointer_sym = "*";
					}
				} else if (p.direction == ParameterDirection.REF) {
					if (type_name != "string") {
						maybe_pointer_sym = "*";
					}
				}
			}

			// TODO: consider special handling of `uint8  *buf, int len`?

			if (type_name == "string") {
				// what about array of char *?  I think we have to let the caller deal with it
				// hopefully overflows don't happen here?
				call_args += "%sC.CString(%s)".printf (pfx, arg_name);
				def_args += "%s%s %sstring".printf (pfx, arg_name, maybe_pointer_sym);
			} else {
				call_args += "%s%s".printf (pfx, arg_name);
				def_args += "%s%s %s%s".printf (pfx, arg_name, maybe_pointer_sym, get_go_type(arg_type));
			}
		}

		if ( ! void_return) {
			defs += "func (_ %s) %s(%s) %s {\n".printf (nsname, camelcase(f.name), def_args, get_go_type(f.return_type));
			if (ret == "string") {
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

	public void walk_method (Method m) {
		debug("walk_method(name: %s)".printf(m.name));
		indent();


		// TODO: "unowned"/static methods

		/*
		bool first = true;
		string cname = CCodeBaseModule.get_ccode_name (m);
		string alias = get_alias (m.name);
		string ret;
		string def_args = "";
		string cdef_args = "";
		string call_args = "";
		bool void_return;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		ret = m.return_type.to_string ();
		ret = get_ctype (is_generic (ret)?  ret : CCodeBaseModule.get_ccode_name (m.return_type));
		if (ret == null)
			error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");

		if (m.is_private_symbol ())
			return;

		string pfx = "";
		string cpfx = "";

		//cdef_args += "%s%s".printf (pfx, "void*");
		if (!is_static) {
			cdef_args += classcname+"*";
			cpfx = ", ";
			pfx = "";
		}
		foreach (var foo in m.get_parameters ()) {
			string arg_name = foo.name;
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null)
				continue;
			string? arg_type = get_ctype (CCodeBaseModule.get_ccode_name (bar));

			if (first) {
				first = false;
			} else cpfx = pfx = ", ";

			// TODO: move to get_ctype
			if (foo.direction != ParameterDirection.IN) {
				var var_name = "";
				if (foo.direction == ParameterDirection.OUT)
					var_name = "ref";
				else
				if (foo.direction == ParameterDirection.REF)
					var_name = "ref";

				if (arg_type.index_of ("*") == -1)
					arg_type += "*";
			}
			if (arg_type=="string") {
				call_args += "%s toStringz(%s)".printf (pfx, arg_name);
				cdef_args += "%s%s %s".printf (cpfx, "immutable(char*)", arg_name);
				def_args += "%s%s %s".printf (pfx, arg_type, arg_name);
			} else {
				call_args += "%s%s".printf (pfx, arg_name);
				def_args += "%s%s %s".printf (pfx, arg_type, arg_name);
				cdef_args += "%s%s %s".printf (cpfx, arg_type, arg_name);
			}
		}

		// object oriented shit
		if (classname == "") {
			//defs += "  %s* %s(%s);\n".printf (ret, cname, cdef_args);
			is_constructor = false;
			is_static = true;
			classname = nspace;
		}
		if (nspace == classname)
			alias = nspace+"_"+alias;
		if (is_constructor) {
			defs += "  %s* %s(%s);\n".printf (classcname, cname, def_args.replace("string","immutable(char*)"));
			extends += "  this (%s) {\n".printf (def_args);
			extends += "    self = %s (%s);\n  }\n".printf (cname, call_args);
		} else {
			if (!is_static)
				call_args = (call_args == "")? "self": "self, " + call_args;
			if (is_static) {
				extends += "  %s %s (%s) {\n".printf (ret, alias, def_args);
				//extends += "  static %s %s (%s) {\n".printf (ret, alias, def_args);
			} else {
				string fret = "";
				if (alias == "free") {
					alias= "~this";
				} else fret = ret;
				extends += "  %s %s (%s) {\n".printf (fret, alias, def_args);
			}
			if (ret.index_of ("std::vector") != -1) {
				int ptr = ret.index_of ("<");
				string iter_type = (ptr==-1)?ret:ret[ptr:ret.length];
				iter_type = iter_type.replace ("<", "");
				iter_type = iter_type.replace (">", "");
				// TODO: Check if iter type exists before failing
				//       instead of hardcoding the most common type '<G>'
				// TODO: Do not construct a generic class if not supported
				//       instead of failing.
				if (iter_type == "G*") // No generic
					error ("Pancake's fault, no <G> type support.\n");
				// TODO: Do not recheck the return_type
				if (m.return_type.to_string ().index_of ("RFList") != -1) {
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
				defs += "  %s %s(%s);\n".printf (ret, cname, cdef_args);
				extends += "    %s %s (%s);\n  }\n".printf (
						void_return?"":"return", cname, call_args);
			}
		}
		*/
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

		bool has_constructor = false;
		foreach (var m in c.get_methods ()) {
			if (m is CreationMethod) {
				has_constructor = true;
				break;
			}
		}
		bool has_destructor = !c.is_compact;

		if (defined_classes.lookup (classname)) {
			debug("already defined");
			dedent();
			return;
		}
		defined_classes.insert (classname, true);

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
//					extends += "  ~this() { %s (o); }\n".printf (freefun);
				}
			} else {
				string? freefun = CCodeBaseModule.get_ccode_free_function (c);
				if (freefun != null) {
					// TODO: add finalizer
//					extends += "  ~this() { %s (o); }\n".printf (freefun);
				}
			}
		}
		foreach (var m in c.get_methods ()) {
			walk_method (m);
		}

		//classname = "";
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

