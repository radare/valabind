/* Copyleft 2012 -- pancake */

using Vala;

public class NodeFFIWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public string[] files;
	public GLib.List<string> includefiles;
	public GLib.List<Method> methods;
	private CodeContext context;
	private FileStream? stream;
	private string symbols;
	private string classname;
	private string classcname;
	private string structs;
	private string exports;
	private string enums;
	private string vectors;
	private string nspace;
	private string modulename;
	private int inner = 0;
	private int count = 0;

	public NodeFFIWriter (string name) {
		enums = "";
		exports = "";
		symbols = "";
		structs = "";
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
		if (name != oname)
			ValabindCompiler.warning ("%s.%s method renamed to %s.%s".printf (
						classname, oname, classname, name));
		return name;
	}

	private string ?get_typeName(DataType ?_type) {
		if(_type == null || _type.data_type == null)
			return null;
		string type = _type.data_type.get_full_name ();
		if (type == "string" || CCodeBaseModule.get_ccode_name (_type.data_type)[0] == 'g')
			return null;
		return type;
	}

	private string get_typeFromC(DataType ?_type, string value) {
		var type = get_typeName(_type);
		if(type == null)
			return "a."+value;
		string stype = type[type.index_of(".")+1:type.length].replace(".", "");
		return "new %s (a.%s)".printf (stype, value);
	}

	private string get_typeToC(DataType ?_type, string value) {
		var type = get_typeName (_type);
		if (type == null)
			return value;
		//var _class = _type.data_type as Class;
		var type_cname = CCodeBaseModule.get_ccode_name (_type);
		return type_cname;
	}

	private string get_ctype (string _type) {
		string? type = _type;
		string? iter_type = null;
		if (type == "null")
			ValabindCompiler.error ("Cannot resolve type");
		if (nspace == null)
			nspace = "";
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
				return "string";
			case "G": /* generic type :: TODO: review */
				case "gconstpointer":
				case "gpointer":
				return "pointer";
			case "gdouble":
				return "double";
			case "gfloat":
				return "float";
			case "break":
				return "_break";
			case "ut8":
			case "uint8":
			case "guint8":
				return "uint8";
			case "gchar":
				return "char";
			case "gchar*":
			case "string":
				return "string"; // ??? 
			case "gint":
				return "int";
			case "gint*":
				return "pointer";
			case "glong":
				return "long";
			case "gchar**":
			case "char**":
			case "char **":
				return "pointer";
			case "st64":
				case "int64":
				case "gint64":
				return "int64";
			case "ut64":
				case "uint64":
				case "guint64":
				return "int64";
			/* XXX swig does not support unsigned char* */
			case "uint8*":
			case "guint8*":
				return "string"; // XXX
			case "guint16":
				return "uint16";
			case "ut32":
			case "uint32":
			case "guint32":
			case "unsigned int":
				return "uint";
			case "bool": // no conversion needed
				case "gboolean":
				return "int"; // XXX bool?
			case "RFList":
			case "RList":
				return "pointer";
			default:
				type = "pointer";
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

	public string walk_field (Field f, string space) {
		var type = get_ctype (CCodeBaseModule.get_ccode_name (f.variable_type));
		string f_cname = CCodeBaseModule.get_ccode_name (f);
		if (type == null || f_cname == "class" || classcname == null)
			return "";
		return "[ '%s', '%s' ]\n".printf (type, f_cname);
	}

	public void walk_class (string pfx, string space, Class c) {
		process_includes (c);
		Method? hasCtor = null;
		bool hasDtor = false;
		bool hasNonStatic = c.get_fields ().size > 0;
		int methods = 0;
		string ctor_name = "";
		string ctor_args = "";

		foreach (var m in c.get_methods ()) {
			methods ++;
			if (m is CreationMethod) {
				hasCtor = m;
				string p = "";
				foreach (var param in m.get_parameters ()) {
					p += param.name; //to_string ();
				}
                		ctor_name = CCodeBaseModule.get_ccode_name (m);
				ctor_args = p;
			}
			if ((m.binding & MemberBinding.STATIC) == 0)
				hasNonStatic = true;
		}
		classcname = CCodeBaseModule.get_ccode_name (c);

		inner++;
		foreach (var x in c.get_structs ()) {
			walk_struct ("", "    ", x);
		}
		// XXX inner classes?
		foreach (var k in c.get_classes ()) {
			walk_class ("", space+"    ", k);
		}
		classname = pfx+c.name;
		classcname = CCodeBaseModule.get_ccode_name (c);
		process_includes (c);
		var fields = c.get_fields ();
		if (fields.size > 0) {
			structs += "var %s = FFI.Struct ([\n".printf (classcname);
			string tab = "\t";
			foreach (var f in c.get_fields ()) {
				var wf = walk_field (f, space+"    ");
				if (wf != "") {
					structs += tab+wf;
					if (tab == "\t") tab = ",\t";
				}
			}
			structs += "]);\n";
		}
		if (inner>1 && false) {
			inner --;
			return;
		}
		string tab = (count++>0)? ", ":"";
		exports += tab+space+"%s : function (%s) {\n".printf (pfx+c.name, ctor_args);

		foreach (var e in c.get_enums ())
			walk_enum (e, space+"    ");
		if (hasNonStatic) {
			if (ctor_name != "")
				exports += space+space+"var o = a.%s(%s);\n".printf (ctor_name, ctor_args);
			string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
			if (freefun != null && freefun != "") {
				exports += "%s    this.delete = function () {\n%s        %s(this.o);\n%s    }\n".printf (space, space, freefun, space);
				hasDtor = true;
			}
			if (ctor_name != "" && !hasDtor)
				exports += "\tthis.delete = function () {\n\t\tthis.free ();\n\t}\n";
		}
		foreach (var m in c.get_methods ())
			walk_method (m, space+"    ", !hasNonStatic);
		classname = "";
		exports += space+"}\n";
	}

	public void walk_struct(string pfx, string space, Struct c) {
		classcname = CCodeBaseModule.get_ccode_name (c);
		process_includes (c);
		var fields = c.get_fields ();
		if (fields.size > 0) {
			structs += "var %s = FFI.Struct ([\n".printf (classcname);
			string tab = "\t";
			foreach (var f in c.get_fields ()) {
				structs += tab+walk_field (f, space+"    ");
				if (tab == "\t") tab = ",\t";
			}
			structs += "]);\n";
		}
	}

	public void walk_enum (Vala.Enum e, string space) {
		process_includes (e);
		exports += "/*\n";
		foreach (var v in e.get_values ())
			exports += "\t%s: %s;\n".printf (
				v.name, CCodeBaseModule.get_ccode_name (v));
		exports += "*/\n";
/*
		foreach (var v in e.get_values ())
			exports += "%s    var %s = %s;\n".printf (
					space, v.name, CCodeBaseModule.get_ccode_name (v));
		exports += "%s}\n".printf (space);
*/
	}

	private inline bool is_generic(string type) {
		return type.index_of ("<") != -1 && type.index_of (">") != -1;
	}

	public void walk_method (Method m, string space, bool dontStatic=false) {
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

		var ret = m.return_type.to_string ();
		if (is_generic (ret))
			ret = get_ctype (ret);
		else
			ret = get_ctype (CCodeBaseModule.get_ccode_name (m.return_type));
		if (ret == null)
			ValabindCompiler.error ("Cannot resolve return type for %s\n".printf (cname));
		bool void_return = (ret == "void");

		/* store sym */
		var xxx = (is_constructor)? "": "\"pointer\"";
		if (symbols != "")
			symbols += ",";
		string tab;
		if (is_static || is_constructor) {
			symbols += "\t\"%s\": [ \"%s\", [".printf (cname, ret);
			tab = "";
		} else {
			symbols += "\t\"%s\": [ \"%s\", [ %s".printf (cname, ret, xxx);
			tab = ", ";
		}
		foreach (var param in m.get_parameters ()) {
			if (param.variable_type == null) continue; // XXX
			string arg_type = get_ctype (CCodeBaseModule.get_ccode_name (param.variable_type));
			if (arg_type == null) arg_type = "pointer";
			symbols += tab + "\"%s\"".printf (arg_type);
			tab = ", ";
		}
		symbols += " ]]\n";

		/* store wrapper */
		string def_args = "";
		bool first = true;
		GLib.List<string> params = new GLib.List<string>();
		double argn = 0;
		foreach (var param in m.get_parameters ()) {
			string? arg_name = param.name;
			if (arg_name == null) break;
			if (param.variable_type == null) {
				ValabindCompiler.warning("%s: %s => null".printf (alias, arg_name));
				return;
			}
			arg_name = "_"+arg_name+"_";

			string pfx;
			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";

			params.append (get_typeToC (param.variable_type, arg_name));
			def_args += "%s%s".printf (pfx, arg_name);
			argn++;
		}
		string call_args = "";
		first = true;
		foreach (var param in m.get_parameters ()) {
			string pfx;
			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";
			call_args += pfx + "_"+param.name+"_";
		}

		string _call;
		if (call_args != "") {
			if (is_static)
			    _call = "%s(%s)".printf (cname, call_args);
			else
			    _call = "%s(o, %s)".printf (cname, call_args);
		} else {
			if (is_static)
			_call = "%s()".printf (cname);
			else
			_call = "%s(o)".printf (cname);
		}
		if (!void_return && !is_constructor)
			_call = "return "+get_typeFromC (m.return_type, _call);
		/* object oriented shit */
		tab = (count++>0)? ", ":"";
		if (classname == "") {
			//exports += "%sfunction %s(%s) {\n%s    %s;\n%s}\n".printf (
			//		space, alias, def_args, space, _call, space);
			exports += "%s%s%s : function (%s) {\n%s    %s;\n%s}\n".printf (
					tab, space, alias, def_args, space, _call, space);
		} else {
			if (!is_constructor) {
				if (is_static && !dontStatic)
					exports += "%sthis.%s = function (%s) {\n".printf (space, alias, def_args);
				else exports += "%sthis.%s = function (%s) {\n".printf (space, alias, def_args);
				exports += "%s    %s;\n%s}\n".printf (space, _call, space);
			}
		}
	}

	public override void visit_class (Class c) {
		walk_class ("", "    ", c);
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
		stream.printf ("/* DO NOT EDIT. automatically generated by valabind */\n");
		stream.printf ("try { var FFI = require (\"ffi\"); }\n");
		stream.printf ("catch (e) { var FFI = require (\"node-ffi\"); }\n");
		stream.printf ("%s\n", structs);
		stream.printf ("%s\n", enums);
		stream.printf ("var a = new FFI.Library (\"lib%s\", {\n", modulename);
		stream.printf ("%s\n", symbols);
		stream.printf ("});\n");
	
		stream.printf ("var obj = {\n");
		stream.printf ("%s\n", exports);
		stream.printf ("}\n");
		stream.printf ("module.exports = obj;\n");

		this.stream = null;
	}
}
