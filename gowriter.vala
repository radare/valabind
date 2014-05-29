/* Copyleft 2014 -- williballenthin */

using Vala;


// TODO: later
/*
public class RootNamespaceFinder : ValabindWriter {
	private GLib.List<Namespace> root_namespaces = new GLib.List<Namespace>();
	private bool has_processed = false;

	public RootNamespaceFinder() {

	}


	private void walk_namespace(Namespace ns) {

	}

	public override void visit_namespace(Namespace ns) {

	}

	private void process() {


		this.has_processed = true;
	}

	public GLib.List<Namespace> get_namespace_roots() {
		if ( ! this.has_processed) {
			this.process();
		}

		return this.root_namespaces;
	}
}
*/


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
		string oname = name;
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
		case "type":
		case "var":
			return "X"+name;
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

	private string cleanup_name(string name) {
		if (name.length == 0) {
			return "";
		} else if (name.length == 1) {
			return name.up();
		} else {
			return name.substring(0, 1).up() + name.substring(1, name.length - 1);
		}
	}

	private string get_golang_type(DataType type) {
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

		// TODO: rename to camelCase

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
	public void walk_field (string class_name, Field f) {
		debug("walk_field(name: %s)".printf(f.name));
		indent();

		// TODO(wb): handle visibility
		if (f.access != SymbolAccessibility.PUBLIC) {
			debug("private.");
			return;
		}

		//if (CCodeBaseModule.get_ccode_array_length (f))
		//	print ("---> array without length\n");

		if (f.get_ctype () == null) {
			//warning (
			//	"Cannot resolve type for field '%s'".printf (f.get_cname ()));
		} else {
			debug("type: %s".printf(CCodeBaseModule.get_ccode_name(f)));
		}

		string name = f.name;

		// TODO: handle generics. ATM, type of `public G data` becomes `func ... GetData() void`
		// TODO: rename to camelCase

		if (name == "type") {
			name = "_type";  // go specific hack, see http://golang.org/cmd/cgo:/"Go references to C"
		}

		defs += "func (c %s) Get%s() %s {\n".printf(class_name, cleanup_name(name), get_golang_type(f.variable_type));
		defs += "    return c.%s\n".printf(name);  // TODO: may need to cast this using `C.*`, but this would require resolving cname for type
		defs += "}\n";

		defs += "func (c %s) Set%s(a %s) {\n".printf(class_name, cleanup_name(name), get_golang_type(f.variable_type));
		defs += "    c.%s = a\n".printf(name);  // TODO: may need to cast this using `C.*`, but this would require resolving cname for type
		defs += "    return\n";
		defs += "}\n";

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

	public void walk_method (Method m) {
		debug("walk_method(name: %s)".printf(m.name));
		indent();
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

		defs += "type %s C.%s\n".printf(classname, classcname);
		foreach (var f in c.get_fields()) {
			walk_field(classname, f);
		}

		/*
		bool has_constructor = false;
		foreach (var m in c.get_methods ())
			if (m is CreationMethod) {
				has_constructor = true;
				break;
			}
		//bool is_static = (c.static_constructor != null);
		bool has_destructor = !c.is_compact;
		//stdout.printf ("class %s %s\n",
		//	classname, c.is_compact.to_string () );

//		if (context.profile == Profile.GOBJECT)
//			classname = "%s_%s".printf (nspace, classname);

		if (defined_classes.lookup (classname))
			return;
		defined_classes.insert (classname, true);

		//extends += "struct %s {\n".printf (classcname);
		// TODO: add fields here
		//extends += "}\n";

		defs += "struct %s {\n".printf (classcname);
		foreach (var f in c.get_fields ())
			walk_field (f);
		defs += "}\n";

		extends += "class %s {\n".printf (classname);
		extends += "  %s *self;\n".printf (classcname);
		//extends += " public:\n";
		foreach (var e in c.get_enums ())
			walk_enum (e);
		//c.static_destructor!=null?"true":"false");
		if (has_destructor && has_constructor) {
			if (CCodeBaseModule.is_reference_counting (c)) {
				string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
				if (freefun != null && freefun != "")
					extends += "  ~this() { %s (o); }\n".printf (freefun);
			} else {
				string? freefun = CCodeBaseModule.get_ccode_free_function (c);
				if (freefun != null)
					extends += "  ~this() { %s (o); }\n".printf (freefun);
			}
		}
		foreach (var m in c.get_methods ())
			walk_method (m);
		extends += "};\n";
		classname = "";
		*/
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
			walk_enum (e);
		}
		foreach (var c in ns.get_structs ()) {
			walk_struct(ns.name == modulename ? ns.name : "", c);
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

