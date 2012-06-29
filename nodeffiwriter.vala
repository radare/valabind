/* Copyleft 2012 -- pancake // eddyb */

using Vala;

public class NodeFFIWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public string[] files;
	public GLib.List<string> includefiles;
	public GLib.List<Method> methods;
	private CodeContext context;
	private FileStream? stream;
	private string classname;
	private string structs;
	private string structFields;
	private string exports;
	private string enums;
	private string vectors;
	private string nspace;
	private string modulename;

	public NodeFFIWriter (string name) {
		enums = "";
		exports = "";
		structs = "";
		structFields = "";
		vectors = "";
		classname = "";
		this.modulename = name;
		this.includefiles = new GLib.List<string> ();
	}

	private string get_alias (string name) {
		string oname = name;
		/*
		   switch (name) {
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
		   }
		   */
		switch (name) {
			case "delete":
				name = "_delete";
				break;
			case "continue":
				name = "_continue";
				break;
		}
		if (name != oname)
			ValabindCompiler.warning ("%s.%s method renamed to %s.%s".printf (
						classname, oname, classname, name));
		return name;
	}

	/*private string? get_typeName(DataType ?_type) {
		if (_type == null || _type.data_type == null)
			return null;
		string type = _type.data_type.get_full_name ();
		if (type == "string" || CCodeBaseModule.get_ccode_name (_type.data_type)[0] == 'g')
			return null;
		return type;
	}

	private string get_typeFromC(DataType ?_type, string value) {
		var type = get_typeName(_type);
		if (type == null)
			return value;
		
		// TODO: DRY (don't repeat yourself) ret/args generation.
		var _delegate = _type as DelegateType;
		if (_delegate != null) {
			var ret = get_ctype (_delegate.get_return_type().to_string ());
			if (ret == null)
				ValabindCompiler.error ("Cannot resolve return type for %s\n".printf (CCodeBaseModule.get_ccode_name (_delegate)));
			
			string args = "";
			foreach (var param in _delegate.get_parameters ()) {
				string arg_type = get_ctype (CCodeBaseModule.get_ccode_name (param.variable_type));
				if (arg_type == null) arg_type = "ptr(types.void)";
				
				if (args != "") args += ", ";
				args += arg_type;
			}
			return "ffi.ForeignFunction(%s, %s, [%s])".printf (value, ret, args);
		}
		string stype = type[type.index_of(".")+1:type.length].replace(".", "");
		return "makeType(types.%s, %s)".printf (stype, value);
	}

	private string get_typeToC(DataType ?type, string value) {
		if (type == null)
			return value;
		
		// TODO: DRY (don't repeat yourself) ret/args generation.
		var _delegate = type as DelegateType;
		if (_delegate != null) {
			var ret = get_ctype (_delegate.get_return_type().to_string ());
			if (ret == null)
				ValabindCompiler.error ("Cannot resolve return type for %s\n".printf (CCodeBaseModule.get_ccode_name (_delegate)));
			
			string args = "";
			foreach (var param in _delegate.get_parameters ()) {
				string arg_type = get_ctype (CCodeBaseModule.get_ccode_name (param.variable_type));
				if (arg_type == null) arg_type = "ptr(types.void)";
				
				if (args != "") args += ", ";
				args += arg_type;
			}
			return "ffi.Callback(%s, [%s], void(0), %s)".printf (ret, args, value);
		}
		return value;
	}*/

	private string get_ctype (string _type) {
		string? type = _type;
		string? iter_type = null;
		if (type == "null")
			ValabindCompiler.error ("Cannot resolve type");
		if (nspace == null)
			nspace = "";
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*"; // XXX why *? (eddyb)
		type = type.replace (".", "");
		if (is_generic (type)) {
			int ptr = type.index_of ("<");
			iter_type = (ptr==-1)?type:type[ptr:type.length];
			iter_type = iter_type.replace ("<", "");
			iter_type = iter_type.replace (">", "");
			iter_type = iter_type.replace (nspace, "");
			type = type.split ("<", 2)[0];
		}
		type = type.replace ("?","").replace(" *", "*");

		switch (type) {
			case "void":
				return "types.void";
			case "const gchar*":
			case "gchar*":
			case "string":
				return "types.Utf8String";
			case "G": /* generic type :: TODO: review */
			case "gconstpointer":
			case "gpointer":
			case "void*":
				return "ptr(types.void)";
			case "gdouble":
				return "types.double";
			case "gfloat":
				return "types.float";
			case "break":
				return "_break";
			case "ut8":
			case "uint8":
			case "guint8":
				return "types.uint8";
			case "gchar":
				return "types.char";
			case "int":
			case "gint":
				return "types.int";
			case "gint*":
				return "ptr(types.int)";
			case "glong":
				return "types.long";
			case "gchar**":
			case "char**":
				return "ptr(types.Utf8String)";
			case "st64":
			case "int64":
			case "gint64":
				return "types.int64";
			case "ut64":
			case "uint64":
			case "guint64":
				return "types.int64";
			case "uint8*":
			case "guint8*":
				return "ptr(types.uint8)";
			case "guint16":
				return "types.uint16";
			case "int32":
			case "gint32":
				return "types.int32";
			case "ut32":
			case "uint32":
			case "guint32":
				return "types.uint32";
			case "guint":
			case "unsigned int":
				return "types.uint";
			case "bool":
			case "gboolean":
				return "types.bool";
			default:
				int nPtr = 0;
				for (; type[type.length-1] == '*'; nPtr++)
					type = type[0:type.length-1];
				type = "types."+type;
				for (; nPtr > 0; nPtr--)
					type = "ptr("+type+")";
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
		foreach (var foo in CCodeBaseModule.get_ccode_header_filenames (s).split (",")) {
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

	public string walk_field (Field f) {
 		var type = get_ctype (CCodeBaseModule.get_ccode_name (f.variable_type));
 		string f_cname = CCodeBaseModule.get_ccode_name (f);
 		if (type == null || f_cname == "class" || classname == "")
 			return "";
 		return "%s: %s".printf (f_cname, type);
	}

	public void walk_class (string pfx, Class c) {
		ValabindCompiler.warning ("> class "+c.name);
		process_includes (c);
		Method? ctor = null;
		bool hasDtor = false;
		bool hasNonStatic = c.get_fields ().size > 0;

		/* avoid showing structs outside the namespace */
		/* fixes a problem with dupped invalid definitions */
		if (nspace == null)
			return;
		foreach (var m in c.get_methods ()) {
			if (m is CreationMethod)
				ctor = m;
			if ((m.binding & MemberBinding.STATIC) == 0)
				hasNonStatic = true;
		}
		
		classname = pfx+c.name;
		process_includes (c);
		structs += "types.%s = Struct();\n".printf (classname);
		var fields = c.get_fields ();
		if (structFields != "")
			structFields += "\n";
		structFields += "/* %s */\n".printf (classname);
		structFields += "struct(types.%s, {".printf (classname);
		string tab = "\n\t";
		foreach (Field f in fields) {
			string wf = walk_field (f);
			if (wf == "") continue;
			structFields += tab+wf;
			if (tab == "\n\t") tab = ",\n\t";
		}
		structFields += "\n});\n";
		
		if (exports != "")
			exports += "\n";
		exports += "/* %s */\n".printf (classname);
		if (ctor != null)
			walk_method (ctor, !hasNonStatic);
		else
			exports += "exports.%s = function %s() {\n\treturn new types.%s;\n};\n".printf (classname, classname, classname);

		foreach (var e in c.get_enums ())
			walk_enum (e);
		if (hasNonStatic) {
			string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
			if (freefun != null && freefun != "") {
				exports += "types.%s.prototype.delete = method('%s', types.void, [ptr(types.%s)]);\n".printf (classname, freefun, classname);
				hasDtor = true;
			}
			if (ctor != null && !hasDtor)
				exports += "types.%s.prototype.delete = defaultDtor;\n".printf (classname);
		}
		foreach (Method m in c.get_methods ())
			if (!(m is CreationMethod))
				walk_method (m, !hasNonStatic);
		
		foreach (Struct x in c.get_structs ())
			walk_struct (pfx+c.name, x);
		
		foreach (Class k in c.get_classes ())
			walk_class (classname = pfx+c.name, k);
		
		classname = "";
		ValabindCompiler.warning ("< class "+c.name);
	}

	public void walk_struct(string pfx, Struct c) {
		ValabindCompiler.warning ("> struct "+c.name);
		classname = pfx+c.name;
		process_includes (c);
		structs += "exports.%s = types.%s = Struct();\n".printf (classname, classname);
		var fields = c.get_fields ();
		if (fields.size > 0) {
			if (structFields != "")
				structFields += "\n";
			structFields += "/* %s */\n".printf (classname);
			structFields += "struct(types.%s, {".printf (classname);
			string tab = "\n\t";
			foreach (Field f in fields) {
				string wf = walk_field (f);
				if (wf == "") continue;
				structFields += tab+wf;
				if (tab == "\n\t") tab = ",\n\t";
			}
			structFields += "\n});\n";
		}
		classname = "";
	}

	public void walk_enum (Vala.Enum e) {
		ValabindCompiler.warning ("> enum "+e.name);
		process_includes (e);
		exports += "/*enum: {\n";
		foreach (var v in e.get_values ())
			exports += "\t%s: %s;\n".printf (
				v.name, CCodeBaseModule.get_ccode_name (v));
		exports += "}*/\n";
/*
		foreach (var v in e.get_values ())
			exports += "\tvar %s = %s;\n".printf (v.name, CCodeBaseModule.get_ccode_name (v));
		exports += "}\n";
*/
	}

	private inline bool is_generic(string type) {
		return type.index_of ("<") != -1 && type.index_of (">") != -1;
	}

	public void walk_method (Method m, bool dontStatic=false) {
		//ValabindCompiler.warning ("> method "+m.name);
		if (m.is_private_symbol ())
			return;
		if (m.name == "cast")
			return;

		process_includes (m);
		string cname = CCodeBaseModule.get_ccode_name (m);
		string alias = get_alias (m.name);
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		var ret = get_ctype ((m.return_type.data_type is Enum) ? "int" : m.return_type.to_string ());
		if (ret == null)
			ValabindCompiler.error ("Cannot resolve return type for %s\n".printf (cname));
		
		if (is_constructor || classname == "")
			exports += "exports.%s = method('%s', %s, [".printf (is_constructor ? classname : alias, cname, is_constructor ? "ptr(types."+classname+")" : ret);
		else if (is_static && !dontStatic)
			exports += "exports.%s.%s = method('%s', %s, [".printf (classname, alias, cname, ret);
		else
			exports += "types.%s.prototype.%s = method('%s', %s, [".printf (classname, "" + alias, cname, ret);
		
		string tab = "";
		if (!is_constructor && !is_static) {
			exports += "ptr(types."+classname+")";
			tab = ", ";
		}
		foreach (Vala.Parameter param in m.get_parameters ()) {
			string arg_type = get_ctype (CCodeBaseModule.get_ccode_name (param.variable_type));
			if (arg_type == null || param.variable_type is DelegateType) arg_type = "ptr(types.void)";
			exports += tab + "%s".printf (arg_type);
			tab = ", ";
		}
		exports += "]%s);\n".printf (is_static && !dontStatic || is_constructor ? ", true" : "");
	}

	public override void visit_class (Class c) {
		ValabindCompiler.warning ("VISIT> class "+c.name);
		walk_class ("", c);
		ValabindCompiler.warning ("VISIT< class "+c.name);
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;
		ValabindCompiler.warning ("VISIT> ns "+ns.name);

		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);

		if (pkgmode && sr.file.filename.index_of (pkgname) == -1)
			return;
		foreach (Enum e in ns.get_enums ())
			walk_enum (e);
		foreach (Struct c in ns.get_structs ()) {
			walk_struct("", c);
			/* TODO: refactor to walk_struct */
			//foreach (var m in c.get_methods ())
			//	walk_method (m, "\t");
			//foreach (var f in c.get_fields ())
			//	walk_field (f, "\t");
		}
		foreach (Class c in ns.get_classes ())
			walk_class ("", c);
		foreach (Field f in ns.get_fields ())
			walk_field (f);
		foreach (Method m in ns.get_methods ())
			walk_method (m);
		//ns.accept_children (this);
		ValabindCompiler.warning ("VISIT< ns "+ns.name);
	}

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		if (this.stream == null)
			error ("Cannot open %s for writing".printf (filename));
		this.context = context;
		context.accept (this);
		stream.printf ("/* DO NOT EDIT. automatically generated by valabind */\n");
		stream.printf ("var ffi = require('ffi'), ref = require('ref'), Struct = require('ref-struct');\n");
		
		stream.printf ("var lib = new ffi.DynamicLibrary('lib%s'+ffi.LIB_EXT);\n", modulename);
		stream.printf ("var types = {}, ptr = exports.ptr = ref.refType;\n\n");
		stream.printf ("for(var i in ref.types)\n\ttypes[i] = ref.types[i];\n\n");
		
		stream.printf ("function struct(s, f) {\n\tif(s._instanceCreated)\n\t\treturn console.warn('Structure redefined, ignoring...');\n\tfor(var i in f)\n\t\ts.defineProperty(i, f[i]);\n\ts._instanceCreated = true, s._class = true;\n}\n");
		stream.printf ("function defaultDtor() {\n\tthis.free && this.free();\n}\n");
		stream.printf ("function fixRetType(r) {\n\treturn (r && r.type && r.type._class) ? r.deref() : r;\n}\n");
		stream.printf ("function method(name, ret, args, static) {\n"+
"\tvar f = ffi.ForeignFunction(lib.get(name), ret, args);\n"+
"\tif(static)\n"+
"\t\treturn function() {\n"+
"\t\t\treturn fixRetType(f.apply(null, arguments));\n"+
"\t\t};\n"+
"\treturn function() {\n"+
"\t\treturn fixRetType(f.apply(null, [this._pointer].concat([].slice.call(arguments))));\n"+
"\t};\n"+
"}\n\n");
		
		stream.printf ("%s", enums);
		stream.printf ("%s\n", structs);
		stream.printf ("%s\n", structFields);
		stream.printf ("%s", exports);

		this.stream = null;
	}
}
