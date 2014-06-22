/* Copyleft 2014 -- williballenthin */

using Vala;


// walks all the datatypes and collects instances of generic classes
// we need this because i cannot figure out how to fetch the "is_generic" attribute
//   from a Vala.Class node object.
// this way, we have to inspect all instances of objects to find what's actually used,
//   and then parse the type name (which includes the <...> specializer).
public class GenericClassFinder : ValabindWriter {
	// see: http://stackoverflow.com/questions/24072692/how-can-i-use-a-hashmap-of-string-in-vala
	GLib.HashTable<string, GLib.HashTable<unowned string, string>> generic_classes = new GLib.HashTable<string, GLib.HashTable<unowned string, string>> (GLib.str_hash, GLib.str_equal);

	inline bool is_generic(DataType d) {
		return (d.to_string().index_of ("<") != -1 && d.to_string().index_of (">") != -1);
	}

	inline bool is_glib(DataType d) {
		return d.to_string().index_of("GLib.") != -1;
	}

	// the base class name, no namespace
	inline string get_class_name(DataType d) {
		string s = d.to_string();
		return s.substring(0, s.index_of_char('<'));
	}

	// `s` should not contain a specializer (<...>)
	inline string strip_namespace(string s) {
		int i1 = s.last_index_of_char('.') + 1;
		return s.substring(i1);
	}

	// the thing in <>
	inline string get_specializer_name(DataType d) {
		string s = d.to_string();
		int i1 = s.index_of_char('<') + 1;
		int i2 = s.index_of_char('>');
		return s.substring(i1, i2 - i1);
	}

	public override void visit_data_type(DataType d) {
		if (is_generic(d) && ( ! is_glib(d))) {
			string c = strip_namespace(get_class_name(d));
			string s = get_specializer_name(d);

			unowned GLib.HashTable<unowned string, string>? inner_set = generic_classes[c];

			if (inner_set == null) {
				var v = new GLib.HashTable<unowned string, string> (GLib.str_hash, GLib.str_equal);
				inner_set = v;
				generic_classes.insert ((owned) c, (owned) v);
			}

			inner_set.replace(s, (owned) s);
		}
	}

	public override void visit_method(Method m) {
		m.accept_children (this);
	}

	public override void visit_field(Field f) {
		f.accept_children (this);
	}

	public override void visit_source_file (SourceFile source) {
		source.accept_children (this);
	}

	public override void visit_namespace(Namespace ns) {
		ns.accept_children (this);
	}

	public override void visit_class(Class c) {
		c.accept_children (this);
	}

	// `.write` is the method that actually does things in a ValabindWriter
	public override void write(string file) {
		context.accept (this);
	}

	// careful, the return object is mutable
	// you probably want to call this after `.write`
	// TODO: should use @get
	public GLib.HashTable<string, GLib.HashTable<unowned string, string>> get_generic_class_instances() {
		return this.generic_classes;
	}
}

public class GoNamer {
	private string pfx;
	public GoNamer(string pfx) {
		this.pfx = pfx;
	}

	// converts symbol names with underscores to camelCase.
	// this function should not be called directly. See `camelcase`.
	// allows trailing '_' characters.
	private static string cleanup_underscores(string name) {
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
			// j will be the index of this character
			string next;
			int j = i + 1;
			while (true) {
				before = name.substring(0, i);
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

			if (j >= name.length - 1) {
				return before + next;
			} else {
				// do rest of string
				return before + next + cleanup_underscores(name.substring(j + 1));
			}
		}
	}

	// see tests t/go/camelcase.vapi
	private static string camelcase(string name) {
		if (name.length == 0) {
			return "";
		} else if (name.length == 1) {
			return name.up();
		} else {
			return name.substring(0, 1).up() + cleanup_underscores(name.substring(1, name.length - 1));
		}
	}

	public string get_field_name(Field f) {
		return camelcase(f.name);
	}

	public string get_method_name(Method m) {
		return camelcase(m.name);
	}

	public string get_parameter_name(Vala.Parameter p) {
		return camelcase(p.name);
	}

	public string get_enum_name(Enum e) {
		return e.name;
	}

	public string get_enum_value_name(Vala.EnumValue v) {
		return v.name;
	}

	public string get_constructor_name(Class c, Method m) {
		string postfix = "";
		if (m.name != ".new") {
			postfix = camelcase(m.name);
		}
		return "New%s%s".printf(get_class_name(c), postfix);
	}

	public string get_class_name(Class c) {
		return "%s%s".printf(this.pfx, camelcase(c.name));
	}

	public string get_struct_name(Struct s) {
		return "%s%s".printf(this.pfx, camelcase(s.name));
	}
}


public class GoSrcWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	HashTable<string,bool> defined_classes = new HashTable<string,bool> (str_hash, str_equal);
	GLib.HashTable<string, GLib.HashTable<unowned string, string>> generic_classes = new GLib.HashTable<string, GLib.HashTable<unowned string, string>> (GLib.str_hash, GLib.str_equal);
	string classname = "";
	string classcname;
	string defs = "";
	string statics = "";
	string extends = "";
	string enums = "";
	string nspace;

	bool needs_unsafe = false;  // set to true if the 'unsafe' package needs to be imported because a void* pointer was encountered

	public GoSrcWriter () {}

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

	public void set_generic_class_instances(GLib.HashTable<string, GLib.HashTable<unowned string, string>> generic_classes) {
		this.generic_classes = generic_classes;
	}

	private string get_alias (string name) {
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

	private string get_ctype (string _type) {
		string type = _type;
		string? iter_type = null;
		if (type == "null")
			error ("Cannot resolve type");
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*";
		type = type.replace (".", "");
		if (is_generic (type)) {
			debug("generic: %s".printf(type));
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

	private bool is_target_file (string path) {
		foreach (var file in source_files)
			if (file == path)
				return true;
		return false;
	}

	public override void visit_source_file (SourceFile source) {
		if (is_target_file (source.filename)) {
			source.accept_children (this);
		}
	}

	private void process_includes (Symbol s) {
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
				includefiles.prepend (foo);
			}
		}
		dedent();
	}

	// converts symbol names with underscores to camelCase.
	// this function should not be called directly. See `camelcase`.
	// allows trailing '_' characters.
	private static string cleanup_underscores(string name) {
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
			// j will be the index of this character
			string next;
			int j = i + 1;
			while (true) {
				before = name.substring(0, i);
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

			if (j >= name.length - 1) {
				return before + next;
			} else {
				// do rest of string
				return before + next + cleanup_underscores(name.substring(j + 1));
			}
		}
	}

	// see tests t/go/camelcase.vapi
	private static string camelcase(string name) {
		if (name.length == 0) {
			return "";
		} else if (name.length == 1) {
			return name.up();
		} else {
			return name.substring(0, 1).up() + cleanup_underscores(name.substring(1, name.length - 1));
		}
	}

	// given a DataType symbol, return a string that contains the Go source code for
	// a type specifier of that type.
	private string get_go_type(DataType type) {
		if (type.to_string() == "G") {
			// TODO
			// error, dont support generics
			warning("We don't support generics");
			debug("generic1: %s".printf(type.to_string()));
			//return;
		}

		if (type.to_string().index_of ("<") != -1) {
			// TODO
			// error, dont support generics
			warning("We don't support generics (2)");
			debug("generic2: %s".printf(type.to_string()));
			//return;
		}

		string typename = get_ctype (type.to_string());
		// we can typecheck to determine if this is a pointer, so throw away '*'
		typename = typename.replace("*", "").strip();
		// if `type` is a pointer, then this will contain the appropriate '*'
		string maybe_pointer_sym = "";
		// if `type` is an array, then this will contain the appropriate "[]"
		string maybe_array_sym = "";
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
	private string walk_field (GoNamer namer, string class_name, Field f, bool is_static=false) {
		string ret = "";
		debug("walk_field(name: %s)".printf(f.name));
		indent();

		// TODO(wb): handle visibility
		if (f.access != SymbolAccessibility.PUBLIC) {
			debug("private.");
			dedent();
			return ret;
		}

		string cname = CCodeBaseModule.get_ccode_name(f);
		string name = get_alias(cname);

		// TODO: handle generics. ATM, type of `public G data` becomes `func ... GetData() void`

		// TODO: make this a function `is_string`
		if (is_string(f)) {
			ret += "func (c %s) Get%s() %s {\n".printf(class_name, namer.get_field_name(f), get_go_type(f.variable_type));
			ret += "    return C.GoString(c.%s)\n".printf(name);
			ret += "}\n";

			ret += "func (c %s) Set%s(a %s) {\n".printf(class_name, namer.get_field_name(f), get_go_type(f.variable_type));
			ret += "    c.%s = C.CString(a)\n".printf(name);
			ret += "    return\n";
			ret += "}\n";
		} else {
			ret += "func (c %s) Get%s() %s {\n".printf(class_name, namer.get_field_name(f), get_go_type(f.variable_type));
			ret += "    return c.%s\n".printf(name);
			ret += "}\n";

			ret += "func (c %s) Set%s(a %s) {\n".printf(class_name, namer.get_field_name(f), get_go_type(f.variable_type));
			ret += "    c.%s = a\n".printf(name);
			ret += "    return\n";
			ret += "}\n";
		}

		dedent();
		return ret;
	}

	private string walk_struct (GoNamer namer, Struct s) {
		string ret = "";
		debug("walk_struct(name: %s)".printf(s.name));
		indent();

		ret += "type %s C.%s\n".printf(namer.get_struct_name(s), CCodeBaseModule.get_ccode_name(s));
		foreach (var f in s.get_fields()) {
			ret += walk_field(namer, s.name == null ? "" : s.name, f);
		}
		ret += "\n";

		dedent();
		return ret;
	}

	private string walk_enum (GoNamer namer, Vala.Enum e) {
		string ret = "";
		var pfx = CCodeBaseModule.get_ccode_prefix(e);
		debug("walk_enum(pfx: %s, name: %s)".printf(pfx, e.name));
		indent();

		ret += "const (\n";
		foreach (var v in e.get_values()) {
			debug("enum(name: %s)".printf(v.name));
			ret += "    %s%s = C.%s%s\n".printf(pfx, namer.get_enum_value_name(v), pfx, v.name);
		}
		ret += ")\n";
		ret += "type %s int".printf(namer.get_enum_name(e));

		dedent();
		return ret;
	}

	inline bool is_generic(string type) {
		return (type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	// is_string: if the parameter is a string
	// arg_name: the C symbol parameter name
	// maybe_pointer_sym: might contain a '*' if needed for the Go symbol. Useful for `out` parameters.
	// arg_type: the parameter type in all its glory
	delegate string parameter_visitor(bool is_string, string arg_name, string maybe_pointer_sym, DataType? arg_type);

	private string get_function_parameters(GoNamer namer, Method f, parameter_visitor v) {
		string args = "";

		bool first = true;
		foreach (var p in f.get_parameters ()) {
			DataType? arg_type = p.variable_type;
			if (arg_type == null) {
				warning("failed to resolve parameter type");
				continue;
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

			if (first) {
				first = false;
			} else {
				args += ", ";
			}

			// TODO: consider special handling of `uint8  *buf, int len`?
			args += v(is_string(p), namer.get_parameter_name(p), maybe_pointer_sym, arg_type);
		}

		return args;
	}

	// BUG: doesn't support '...' parameters
	private string get_function_declaration_parameters(GoNamer namer, Method f) {
		parameter_visitor formatter = (is_string, arg_name, maybe_pointer_sym, arg_type) => {
			if (is_string) {
				// what about array of char *?  I think we have to let the caller deal with it
				// hopefully overflows don't happen here?
				return "%s %sstring".printf (arg_name, maybe_pointer_sym);
			} else {
				return "%s %s%s".printf (arg_name, maybe_pointer_sym, get_go_type(arg_type));
			}
		};
		return get_function_parameters(namer, f, formatter);
	}

	// BUG: doesn't support '...' parameters
	private string get_function_call_parameters(GoNamer namer, Method f) {
		parameter_visitor formatter = (is_string, arg_name, maybe_pointer_sym, arg_type) => {
			if (is_string) {
				// what about array of char *?  I think we have to let the caller deal with it
				// hopefully overflows don't happen here?
				return "C.CString(%s)".printf (arg_name);
			} else {
				return "%s".printf (arg_name);
			}
		};
		return get_function_parameters(namer, f, formatter);
	}

	// see tests t/go/namespace_functions.vapi
	private string walk_function(GoNamer namer, string nsname, Method f) {
		string ret = "";
		string cname = CCodeBaseModule.get_ccode_name(f);
		debug("walk_function(ns: %s, name: %s)".printf(nsname, cname));
		indent();

		bool void_return;
		if (f is CreationMethod) {
			warning("constructor where function expected");
		}
		if (f.is_private_symbol ()) {
			debug("private.");
			dedent();
			return ret;
		}

		string return_value_type_name = f.return_type.to_string ();
		// TODO: generics
		return_value_type_name = get_ctype (is_generic (return_value_type_name)?  return_value_type_name : CCodeBaseModule.get_ccode_name (f.return_type));
		if (return_value_type_name == null) {
			error ("Cannot resolve return type for %s\n".printf (cname));
		}
		void_return = (return_value_type_name == "void");

		string def_args = get_function_declaration_parameters(namer, f);
		string call_args = get_function_call_parameters(namer, f);
		if ( ! void_return) {
			ret += "func (_ %s) %s(%s) %s {\n".printf (nsname, namer.get_method_name(f), def_args, get_go_type(f.return_type));
			if (is_string(f.return_type)) {
				// we have to let the caller deal with array of char *
				// what happens if there are embedded nulls?
				ret += "    return C.GoString(%s(%s))\n".printf (cname, call_args);
			} else {
				// what about void*?
				ret += "    return %s(%s)\n".printf (cname, call_args);
			}
		} else {
			ret += "func (_ %s) %s(%s) {\n".printf (nsname, namer.get_method_name(f), def_args);
			ret += "    %s(%s)\n".printf (cname, call_args);
		}
		ret += "}\n";

		dedent();
		return ret;
	}

	private string walk_method (GoNamer namer, string classname, Method m) {
		string ret = "";
		string cname = CCodeBaseModule.get_ccode_name(m);
		debug("walk_method(ns: %s, name: %s)".printf(classname, cname));
		indent();

		// TODO: "unowned"/static methods
		bool void_return;
		if (m is CreationMethod) {
			warning("constructor where function expected");
		}
		if (m.is_private_symbol ()) {
			debug("private.");
			dedent();
			return ret;
		}

		string return_value_type_name = m.return_type.to_string ();
		// TODO: generics
		return_value_type_name = get_ctype (is_generic (return_value_type_name)?  return_value_type_name : CCodeBaseModule.get_ccode_name (m.return_type));
		if (return_value_type_name == null) {
			error ("Cannot resolve return type for %s\n".printf (cname));
		}
		void_return = (return_value_type_name == "void");

		string def_args = get_function_declaration_parameters(namer, m);
		string call_args = get_function_call_parameters(namer, m);

		ret += "func (this *%s) %s(".printf(classname, namer.get_method_name(m));
		if (def_args != "") {
			ret += "%s".printf(def_args);
		}
		ret += ") ";
		if ( ! void_return) {
			ret += "%s ".printf(get_go_type(m.return_type));
		}
		ret += "{\n";
		ret += "    ";
		if ( ! void_return) {
			ret += "return ";
			if (is_string(m.return_type)) {
				// TODO: use wrap_type function
				ret += "C.GoString(";
			}

			ret += "%s(this".printf(cname);
			if (call_args != "") {
				ret += ", %s".printf(call_args);
			}
			ret += ")";

			if (is_string(m.return_type)) {
				ret += ")";
			}
			ret += "\n";
		} else {
			ret += "%s(this".printf(cname);
			if (call_args != "") {
				ret += ", %s".printf(call_args);
			}
			ret += ")\n";
		}
		ret += "}\n";

		dedent();
		return ret;
	}

	private string walk_constructor(GoNamer namer, Class c, Method m, string free_function) {
		string ret = "";
		string classname = namer.get_class_name(c);
		string cname = CCodeBaseModule.get_ccode_name(m);
		debug("walk_method(ns: %s, name: %s)".printf(classname, cname));
		indent();

		// TODO: "unowned"/static methods
		bool void_return;
		if (m.is_private_symbol ()) {
			debug("private.");
			dedent();
			return ret;
		}

		string return_value_type_name = m.return_type.to_string ();
		// TODO: generics
		return_value_type_name = get_ctype (is_generic (return_value_type_name)?  return_value_type_name : CCodeBaseModule.get_ccode_name (m.return_type));
		if (return_value_type_name == null) {
			error ("Cannot resolve return type for %s\n".printf (cname));
		}
		void_return = (return_value_type_name == "void");

		string def_args = get_function_declaration_parameters(namer, m);
		string call_args = get_function_call_parameters(namer, m);

		string postfix = "";
		if (m.name != ".new") {
			debug("camelcase: %s".printf(m.name));
			postfix = camelcase(m.name);
		}
		ret += "func %s(".printf(namer.get_constructor_name(c, m));
		if (def_args != "") {
			ret += "%s".printf(def_args);
		}
		ret += ") *%s {\n".printf(classname);

		ret += "    var ret *%s\n".printf(classname);
		ret += "    ret = C.%s(".printf(cname);
		if (call_args != "") {
			ret += "%s".printf(call_args);
		}
		ret += ")\n";
		if (free_function != "") {
			ret += "    SetFinalizer(ret, func(r *%s) {\n".printf(classname);
			ret += "        C.%s(r)\n".printf(free_function);
			ret += "    })\n";
		}
		ret += "    return ret\n";
		ret += "}\n";

		dedent();
		return ret;
	}

	private string get_class_src(GoNamer namer, Class c) {
		string ret = "";
		foreach (var k in c.get_structs ()) {
			ret += walk_struct (namer, k);
		}
		foreach (var k in c.get_classes ()) {
			ret += walk_class (k);
		}
		classname = namer.get_class_name(c);
		classcname = CCodeBaseModule.get_ccode_name (c);

		process_includes (c);
		if (defined_classes.lookup (classname)) {
			debug("already defined");
			dedent();
			return ret;
		}
		defined_classes.insert (classname, true);

		bool has_constructor = false;
		foreach (var m in c.get_methods ()) {
			if (m is CreationMethod) {
				has_constructor = true;
				break;
			}
		}

		ret += "type %s C.%s\n".printf(classname, classcname);
		foreach (var f in c.get_fields()) {
			ret += walk_field(namer, classname, f);
		}

		foreach (var e in c.get_enums ()) {
			ret += walk_enum (namer, e);
		}

		foreach (var m in c.get_methods ()) {
			if ( ! (m is CreationMethod)) {
				ret += walk_method (namer, classname, m);
			} else {
				debug("constructor: %s::%s".printf(classname, m.name));
				string free_function = "";
				if (CCodeBaseModule.is_reference_counting (c)) {
					string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
					if (freefun != null && freefun != "") {
						debug("destructor (unref): %s".printf(freefun));
						free_function = freefun;
					}
				} else {
					// BUG?: this method always seems to return a free function (default: ${cprefix}_free)
					//   even if there is no `free_function` defined in the `CCode` block
					// see test in t/go/classes.vapi
					string? freefun = CCodeBaseModule.get_ccode_free_function (c);
					if (freefun != null) {
						debug("destructor (free): %s".printf(freefun));
						free_function = freefun;
					}
				}
				ret += walk_constructor(namer, c, m, free_function);
			}
		}

		ret += "\n";
		dedent();
		return ret;
	}

	private string walk_class (Class c) {
		string ret = "";
		debug("walk_class(name: %s)".printf(c.name));

		indent();

		if (this.generic_classes.contains(c.name)) {
			debug("generic class");
			indent();

			// TODO: might need to change the prefix
			GoNamer namer = new GoNamer("");

			foreach (var t in c.get_type_parameters()) {
				debug("tp: %s".printf(t.name));
			}

			unowned GLib.HashTable<unowned string, string> specializations;
			specializations = this.generic_classes.lookup(c.name);
			specializations.foreach((k, v) => {
				debug("specialization: %s".printf(k));
				indent();

				// stuff
				ret += "// type %s_%s\n".printf(c.name, camelcase(v));


				dedent();
			});
			dedent();
			ret += get_class_src(namer, c);
		} else {
			// TODO: might need to change the prefix
			GoNamer namer = new GoNamer("");
			ret += get_class_src(namer, c);
		}

		dedent();
		return ret;
	}


	// go doesn't really support namespaces. Often code is namespaced by
	//  directory hierarchy, but thats for code organization.
	// we eat namespaces here, as they don't generate anything besides their children.
	public override void visit_namespace (Namespace ns) {
		string ret = "";
		debug("walk_namespace(name: %s)".printf(ns.name));
		indent();
		if (ns.name == "") {
			return;
		}

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
			ret += walk_enum (new GoNamer(ns.name == modulename ? ns.name : ""), e);
		}
		foreach (var c in ns.get_structs()) {
			ret += walk_struct(new GoNamer(ns.name == modulename ? ns.name : ""), c);
		}
		if (ns.get_methods().size + ns.get_fields().size > 0) {
			// Go only does namespacing through file system paths, whish is
			//  probably not appropriate/feasible here
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
			ret += "type %s int\n".printf(fake_ns_name);
			foreach (var c in ns.get_fields()) {
				ret += walk_field(new GoNamer(ns.name == modulename ? ns.name : ""), fake_ns_name, c);
			}
			foreach (var m in ns.get_methods()) {
				ret += walk_function(new GoNamer(ns.name == modulename ? ns.name : ""), fake_ns_name, m);
			}
			ret += "var %s %s\n".printf(ns.name, fake_ns_name);
			ret += "\n";
		}
		foreach (var c in ns.get_classes ()) {
			ret += walk_class (c); //ns.name, c);
		}

		dedent();
		defs += ret;
	}

	public override void write (string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null) {
			error ("Cannot open %s for writing".printf (file));
		}

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

public class GoWriter : ValabindWriter {
	public GoWriter() {}

	public override string get_filename (string base_name) {
		return base_name + ".go";
	}

	private void clone_writer_config(ValabindWriter w) {
		w.modulename = this.modulename;
		w.library = this.library;
		w.include_dirs = this.include_dirs;
		w.namespaces = this.namespaces;

		w.init(this.vapidir, this.glibmode);
		foreach (var pkg in this.packages) {
			w.add_external_package(pkg);
		}
		foreach (var def in this.defines) {
			w.add_define(def);
		}
		foreach (var f in this.source_files) {
			w.add_source_file(f);
		}
	}

	public override void write (string file) {
		var f = new GenericClassFinder();
		this.clone_writer_config(f);
		f.parse();
		f.write(file);

		var g = new GoSrcWriter();
		this.clone_writer_config(g);
		g.set_generic_class_instances(f.get_generic_class_instances());

		g.parse();
		g.write(file);
	}
}


