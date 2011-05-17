/* Copyleft 2009-2011 -- eddyb */

using Vala;

public class GearWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public string[] files;
	public GLib.List<string> includefiles;
	public GLib.List<Method> methods;
	private CodeContext context;
	private FileStream? stream;
	private string classname;
	private string classcname;
	private string exports;
	private string enums;
	private string vectors;
	private string nspace;
	private string modulename;

	public GearWriter (string name) {
		enums = "";
		exports = "";
		vectors = "";
		classname = "";
		this.modulename = name;
		this.includefiles = new GLib.List<string> ();
	}

	private string get_alias (string name) {
		string oname = name;
		switch (name) {
			/*
			   case "use":
			   return "_use";

			   case "cmd":
			   name = "_cmd";
			   break;
			   case "def":
			   name = "_def";
			   break;
			   case "print":
			   name = "_print";
			   break;
			   case "del":
			   name = "_del";
			   break;
			   case "from":
			   name = "_from";
			   break;
			 */		case "continue":
			name = "cont";
			break;
			case "class":
				name = "_class";
			break;
			case "template":
				name = "_template";
			break;
		}
		if (name != oname)
			ValabindCompiler.warning ("%s.%s method renamed to %s.%s".printf (
				classname, oname, classname, name));
		return name;
	}

	private string ?get_typeName(DataType ?_type) {
		if(_type == null || _type.data_type == null)
			return null;
		string type = _type.data_type.get_full_name ();
		if(type == "string" || _type.data_type.get_cname()[0] == 'g')
			return null;
		return type;
	}

	private string get_typeFromC(DataType ?_type, string value) {
		var type = get_typeName(_type);
		if(type == null)
			return "Value("+value+")";
		return "require(\"%s\")[\"%s\"].newInstance(%s)".printf (
			modulename, type[type.index_of(".")+1:type.length].replace(".", "\"][\""), value);
	}

	private string get_typeToC(DataType ?_type, string value) {
		var type = get_typeName(_type);
		if(type == null)
			return value;
		//var _class = _type.data_type as Class;
		var _struct = _type.data_type as Struct;
		if(_struct != null && _struct.is_integer_type())
			return "%s.to<%s>()".printf(value, _type.get_cname());
		return "%s[\"self\"].to<%s>()".printf(value, (_type.get_cname()+"*").replace("**","*"));
	}

	private string get_ctype (string _type) {
		string type = _type;
		string? iter_type = null;
		if (type == "null")
			ValabindCompiler.error ("Cannot resolve type");
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*";
		//type = type.replace (".", "");
		if (is_generic (type)) {
			int ptr = type.index_of ("<");
			iter_type = (ptr==-1)?type:type[ptr:type.length];
			iter_type = iter_type.replace ("<", "");
			iter_type = iter_type.replace (">", "");
			iter_type = iter_type.replace (nspace, "");
			type = type.split ("<", 2)[0];
		}
		type = type.replace ("?","");

		switch (type) {
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
			return "char**";
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
			return "char*"; // ??? 
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

	private bool is_target_file (string path) {
		foreach (var file in files)
			if (file == path)
				return true;
		return false;
	}

	public override void visit_source_file (SourceFile source) {
		if (is_target_file (source.filename))
			source.accept_children (this);
	}

	public void process_includes (Symbol s) {
		foreach (var foo in s.get_cheader_filenames ()) {
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

	public void walk_field (Field f, string space) {
		// if (f.variable_type.get_ctype () == null) {
		//     ValabindCompiler.warning ("Cannot resolve type for field '%s' == %s".printf (f.get_cname (), f.variable_type.get_cname()));
		//} else ValabindCompiler.warning ("Type for %s\n".printf (f.get_cname ()));
		if (f.access == SymbolAccessibility.PRIVATE) {
			//print ("---> field is private XXX\n");
			return;
		}
		//if (f.no_array_length)
		//    print ("---> array without length\n");
		var type = get_ctype(f.variable_type.get_cname());
		if (type == null || f.get_cname() == "class" || classcname == null)
			return;
		string name = get_alias(f.name);
		if (type == "char*" || type == "const char*") {
			exports += "%sgetter %s() {\n%s    return String(this[\"self\"].to<%s*>()->%s);\n%s}\n".printf (space, name, space, classcname, name, space);
			exports += "%ssetter %s(value) {\n%s    setString(this[\"self\"].to<%s*>()->%s, value);\n%s}\n".printf (space, name, space, classcname, name, space);
		} else if (type == "unsigned char*") { /// \todo Binary Buffers
			ValabindCompiler.warning ("TODO: %s is a buffer".printf (f.get_cname ()));
		} else {
			if(type[type.length-1]=='*' && get_typeName(f.variable_type) == null) {
				ValabindCompiler.warning ("TODO: %s is a pointer (%s)".printf (f.get_cname (), f.variable_type.get_cname()));
				return;
			}
			exports += "%sgetter %s() {\n%s    return %s;\n%s}\n".printf (space, name, space, get_typeFromC(f.variable_type, "this[\"self\"].to<%s*>()->%s".printf(classcname, name)), space);
			if(type[0] > 'A' && type[0] < 'Z') {
				ValabindCompiler.warning ("TODO: %s is custom (%s)".printf (f.get_cname (), type));
				return;
			}
			exports += "%ssetter %s(value) {\n%s    this[\"self\"].to<%s*>()->%s = %s;\n%s}\n".printf (space, name, space, classcname, name, get_typeToC(f.variable_type, "value"), space);
		}
	}

	public void walk_class (string pfx, string space, Class c) {
		process_includes (c);
		bool hasCtor = false, hasDtor = false, hasNonStatic = c.get_fields().size > 0;
		foreach (var m in c.get_methods ()) {
			if(m is CreationMethod)
				hasCtor = true;
			if((m.binding & MemberBinding.STATIC) == 0)
				hasNonStatic = true;
		}
		exports += space+"%s %s {\n".printf (hasNonStatic?"class":"object", pfx+c.name);
		foreach (var k in c.get_classes ())
			walk_class ("", space+"    ", k);
		classname = pfx+c.name;
		classcname = c.get_cname ();
		process_includes (c);
		foreach (var e in c.get_enums ())
			walk_enum (e, space+"    ");
		if(hasNonStatic) {
			if(!hasCtor)
				exports += "%s    function %s() {\n%s        this[\"self\"] = Internal(new %s);\n%s    }\n".printf (space, classname, space, classcname, space);
			exports += "%s    function %s(_self) {\n%s        this[\"self\"] = Internal(_self);\n%s    }\n".printf (space, classname, space, space);
			if (c.is_reference_counting ()) {
				string? freefun = c.get_unref_function ();
				if (freefun != null && freefun != "") {
					exports += "%s    function __%s() {\n%s        %s(this[\"self\"]);\n%s    }\n".printf (space, classname, space, freefun, space);
					hasDtor = true;
				}
			} else {
				string? freefun = c.get_free_function ();
				if (freefun != null && freefun != "") {
					exports += "%s    function __%s() {\n%s        %s(this[\"self\"]);\n%s    }\n".printf (space, classname, space, freefun, space);
					hasDtor = true;
				}
			}
			if(!hasDtor)
				exports += "%s    function __%s() {\n%s        delete this[\"self\"].to<%s*>();\n%s    }\n".printf (space, classname, space, classcname, space);
		}
		foreach (var m in c.get_methods ())
			walk_method (m, space+"    ", !hasNonStatic);
		foreach (var f in c.get_fields ())
			walk_field (f, space+"    ");
		exports += space+"}\n";
		classname = "";
	}

	public void walk_struct(string pfx, string space, Struct c) {
		process_includes (c);
		bool hasCtor = false, hasDtor = false, hasNonStatic = c.get_fields().size > 0;
		foreach (var m in c.get_methods ()) {
			if(m is CreationMethod)
				hasCtor = true;
			if((m.binding & MemberBinding.STATIC) == 0)
				hasNonStatic = true;
		}
		exports += space+"%s %s {\n".printf (hasNonStatic?"class":"object", pfx+c.name);
		classname = pfx+c.name;
		classcname = c.get_cname ();
		process_includes (c);
		if(hasNonStatic) {
			if(!hasCtor)
				exports += "%s    function %s() {\n%s        this[\"self\"] = Internal(new %s);\n%s    }\n".printf (space, classname, space, classcname, space);
			exports += "%s    function %s(_self) {\n%s        this[\"self\"] = Internal(_self);\n%s    }\n".printf (space, classname, space, space);
			if (c.is_reference_counting ()) {
				string? freefun = c.get_unref_function ();
				if (freefun != null && freefun != "") {
					exports += "%s    function __%s() {\n%s        %s(this[\"self\"]);\n%s    }\n".printf (space, classname, space, freefun, space);
					hasDtor = true;
				}
			} else {
				string? freefun = c.get_free_function ();
				if (freefun != null && freefun != "") {
					exports += "%s    function __%s() {\n%s        %s(this[\"self\"]);\n%s    }\n".printf (space, classname, space, freefun, space);
					hasDtor = true;
				}
			}
			if(!hasDtor)
				exports += "%s    function __%s() {\n%s        delete this[\"self\"].to<%s*>();\n%s    }\n".printf (space, classname, space, classcname, space);
		}
		foreach (var m in c.get_methods ())
			walk_method (m, space+"    ", !hasNonStatic);
		foreach (var f in c.get_fields ())
			walk_field (f, space+"    ");
		exports += space+"}\n";
		classname = "";
	}

	public void walk_enum (Vala.Enum e, string space) {
		process_includes (e);
		exports += "\n%sobject %s {\n".printf (space, e.name);
		foreach (var v in e.get_values ())
			exports += "%s    var %s = %s;\n".printf (space, v.name, v.get_cname ());
		exports += "%s}\n".printf (space);
	}

	private inline bool is_generic(string type) {
		return type.index_of ("<") != -1 && type.index_of (">") != -1;
	}

	public void walk_method (Method m, string space, bool dontStatic=false) {
		if (m.is_private_symbol ())
			return;

		process_includes (m);
		string cname = m.get_cname ();
		string alias = get_alias (m.name);
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		var ret = m.return_type.to_string ();
		if (is_generic (ret))
			ret = get_ctype (ret);
		else
			ret = get_ctype (m.return_type.get_cname ());
		if (ret == null)
			ValabindCompiler.error ("Cannot resolve return type for %s\n".printf (cname));
		bool void_return = (ret == "void");

		string def_args = "";
		bool first = true;
		GLib.List<string> params = new GLib.List<string>();
		double argn = 0;
		foreach (var param in m.get_parameters ()) {
			string arg_name = param.name;
			if (param.variable_type == null) {
				ValabindCompiler.warning("%s: %s => null".printf (alias, arg_name));
				return;
			}
			arg_name = "_"+arg_name+"_";
			string arg_type = get_ctype (param.variable_type.get_cname ());

			string pfx;
			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";

			if(arg_type=="char*" || arg_type=="const char*") {
				params.append(arg_name+".to<String>()");
				if (param.variable_type.is_array())
					params.append(arg_name+".length()");
			} else params.append(get_typeToC(param.variable_type, arg_name));
			def_args += "%s%s".printf (pfx, arg_name);
			argn++;
		}
		if (classname != "" && !is_static && !is_constructor) {
			int instance_offset = (int)m.cinstance_parameter_position;
			if(instance_offset < 0)
				instance_offset = (int)params.length() + 1 + instance_offset;
			params.insert("this[\"self\"]", instance_offset);
		}
		string call_args = "";
		first = true;
		foreach (var param in params) {

			string pfx;
			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";
			call_args += pfx + param;
		}

		string _call = "%s(%s)".printf(cname, call_args);
		if (!void_return && !is_constructor)
			_call = "return "+get_typeFromC(m.return_type, _call);
		/* object oriented shit */
		if (classname == "")
			exports += "%sfunction %s(%s) {\n%s    %s;\n%s}\n".printf(space, alias, def_args, space, _call, space);
		else {
			if (is_constructor)
				exports += "%sfunction %s(%s) {\n%s    this[\"self\"] = Internal(%s(%s));\n%s}\n".printf (space, classname, def_args, space, cname, call_args, space);
			else {
				if (is_static && !dontStatic)
					exports += "%sstatic function %s(%s) {\n".printf (space, alias, def_args);
				else exports += "%sfunction %s(%s) {\n".printf (space, alias, def_args);
				exports += "%s    %s;\n%s}\n".printf (space, _call, space);
			}
		}
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;

		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);

		if (pkgmode && sr.file.filename.index_of (pkgname) == -1)
			return;
		foreach (var f in ns.get_fields ())
			walk_field (f, "    ");
		foreach (var e in ns.get_enums ())
			walk_enum (e, "    ");
		foreach (var c in ns.get_structs ()) {
			walk_struct("", "    ", c);
			/* TODO: refactor to walk_struct */
			//foreach (var m in c.get_methods ())
			//    walk_method (m, "    ");
			//foreach (var f in c.get_fields ())
			//    walk_field (f, "    ");
		}
		foreach (var m in ns.get_methods ())
			walk_method (m, "    ", true);
		foreach (var c in ns.get_classes ())
			walk_class ("", "    ", c);
		//ns.accept_children (this);
	}

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		if (this.stream == null)
			error ("Cannot open %s for writing".printf (filename));
		this.context = context;
		context.accept (this);
		if (includefiles.length () > 0) {
			stream.printf ("top {\n");
			foreach (var inc in includefiles)
				stream.printf ("    #include <%s>\n", inc);
			stream.printf ("    void setString(char *&&a, String b) {if(b.empty() || !b.length()){a[0]=0;return;}size_t i;for(i = 0; i < b.length(); i++)a[i]=(*b)[i];a[i]=0;}\n");
			stream.printf ("    void setString(const char *&&a, String b) {}\n");
			stream.printf ("    void setString(char *&a, String b) {if(a)delete [] a;String c = b;a = *c;c.clear();}\n");
			stream.printf ("    void setString(const char *&a, String b) {if(a)delete [] a;String c = b;a = *c;c.clear();}\n");
			stream.printf ("}\n");
		}
		stream.printf ("module %s {\n", modulename);

		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", exports);

		stream.printf ("}\n");

		this.stream = null;
	}
}
