/* Copyright 2009-2015 -- pancake // nopcode.org */

using Vala;

public class CxxWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	public GLib.List<Method> methods;
	string classname = "";
	string classcname;
	string externs = "";
	string statics = "";
	string extends = "";
	string enums = "";
	string vectors = "";
	string nspace;

	public CxxWriter () {
	}

	public override string get_filename (string base_name) {
		return base_name+".cxx";
	}

	string get_alias (string name) {
		string oname = name;
		switch (name) {
		case "not_eq":
		case "or_eq":
		case "xor_eq":
		case "and_eq":
		case "or":
		case "xor":
		case "not":
		case "and":
		case "break":
		case "while":
		case "print":
		case "new":
		case "for":
		case "if":
		case "case":
		case "delete":
		case "continue":
			return "_"+name;
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

		switch (type) {
		case "const gchar*":
			return "const char*";
		case "G": /* generic type :: TODO: review */
		case "gconstpointer":
		case "gpointer":
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
			return "unsigned char";
		case "gchar**":
			return "char **";
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
			return "char *"; // ???
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

	bool is_target_file (string path) {
		// FIXME implement the new method with use_namespace instead
		foreach (var file in source_files)
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

	public void walk_field (Field f) {
		if (f.get_ctype () == null) {
			//warning (
			//	"Cannot resolve type for field '%s'".printf (f.get_cname ()));
		} else {
			warning ("Type for %s\n".printf (
				CCodeBaseModule.get_ccode_name (f)));
		}
		//if (f.access == Accessibility.PRIVATE)
		//	print ("---> field is private XXX\n");
		//if (CCodeBaseModule.get_ccode_array_length (f))
		//	print ("---> array without length\n");
	}

	HashTable<string,bool> defined_classes = new HashTable<string,bool> (str_hash, str_equal);

	public void walk_class (string pfx, Class c) {
		foreach (var k in c.get_classes ())
			walk_class (c.name, k);
		classname = pfx+c.name;
		classcname = CCodeBaseModule.get_ccode_name (c);

		process_includes (c);

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

		if (context.profile == Profile.GOBJECT)
			classname = "%s_%s".printf (nspace, classname);

		if (defined_classes.lookup (classname))
			return;
		defined_classes.insert (classname, true);

		if (context.profile == Profile.GOBJECT) extends += "class %s_%s {\n".printf (modulename, classcname);
		else extends += "class %s_%s {\n".printf (modulename, classname);
		//if (has_destructor && has_constructor)
			extends += " %s *self;\n".printf (classname);
		extends += " public:\n";
		foreach (var e in c.get_enums ())
			walk_enum (e);
		foreach (var f in c.get_fields ())
			walk_field (f);
		//c.static_destructor!=null?"true":"false");
		if (has_destructor && has_constructor) {
			if (CCodeBaseModule.is_reference_counting (c)) {
				string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
				if (freefun != null)
					extends += "  ~%s_%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
			} else {
				string? freefun = CCodeBaseModule.get_ccode_free_function (c);
				if (freefun != null)
					extends += "  ~%s_%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
			}
		}
		foreach (var m in c.get_methods ())
			walk_method (m);
		extends += "};\n";
		classname = "";
	}

	public void walk_enum (Vala.Enum e) {
#if not_required
		var enumname = classname + e.name;
		var tmp = "%{\n";
		enums += "/* enum: %s (%s) */\n".printf (
			e.name, CCodeBaseModule.get_ccode_name (e));
		enums += "enum %s {\n".printf (enumname);
		tmp += "#define %s long int\n".printf (enumname); // XXX: Use cname?
		foreach (var v in e.get_values ()) {
			enums += "  %s_%s,\n".printf (e.name, v.name);
			tmp += "#define %s_%s %s\n".printf (e.name, v.name,
				CCodeBaseModule.get_ccode_name (v));
		}
		enums += "};\n";
		enums += tmp + "%}\n";
#endif
	}

	inline bool is_generic(string type) {
		return (type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	public void walk_method (Method m) {
		bool first = true;
		string cname = CCodeBaseModule.get_ccode_name (m);
		string alias = get_alias (m.name);
		string ret;
		string def_args = "";
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

		string applys = "";
		string clears = "";
		string pfx = "";
		foreach (var foo in m.get_parameters ()) {
			string arg_name = foo.name;
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null)
				continue;
			string? arg_type = get_ctype (CCodeBaseModule.get_ccode_name (bar));

			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";

			/* TODO: move to get_ctype */
			if (foo.direction != ParameterDirection.IN) {
				var var_name = "";
				if (foo.direction == ParameterDirection.OUT)
					var_name = "OUTPUT";
				else
				if (foo.direction == ParameterDirection.REF)
					var_name = "INOUT";

				if (arg_type.index_of ("*") == -1)
					arg_type += "*";
				applys += "  %%apply %s %s { %s %s };\n".printf (
					arg_type, var_name, arg_type, arg_name);
				//clears += "  %%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args += "%s%s".printf (pfx, arg_name);
			def_args += "%s%s %s".printf (pfx, arg_type, arg_name);
		}

		/* object oriented shit */
		if (classname == "") {
			externs += "extern %s %s (%s);\n".printf (ret, cname, def_args);
			is_constructor = false;
			is_static = true;
			classname = nspace;
		} //else {
		if (nspace == classname)
			alias = nspace+"_"+alias;
		if (is_constructor) {
			externs += "extern %s* %s (%s);\n".printf (classcname, cname, def_args);
			//extends += applys;
			extends += "  %s_%s (%s) {\n".printf (modulename, classname, def_args);
			if (context.profile == Profile.GOBJECT)
				extends += "    g_type_init ();\n";
			extends += "    self = %s (%s);\n  }\n".printf (cname, call_args);
			extends += clears;
		} else {
			if (!is_static)
				call_args = (call_args == "")? "self": "self, " + call_args;
			//				externs += "extern %s %s (%s*, %s);\n".printf (ret, cname, classname, def_args);
			//		extends += applys;
			if (is_static)
				extends += "  static %s %s (%s) {\n".printf (ret, alias, def_args);
			else extends += "  %s %s (%s) {\n".printf (ret, alias, def_args);
			if (ret.index_of ("std::vector") != -1) {
				int ptr = ret.index_of ("<");
				string iter_type = (ptr==-1)?ret:ret[ptr:ret.length];
				iter_type = iter_type.replace ("<", "");
				iter_type = iter_type.replace (">", "");
				// TODO: Check if iter type exists before failing
				//       instead of hardcoding the most common type '<G>'
				// TODO: Do not construct a generic class if not supported
				//       instead of failing.
				if (iter_type == "G*") /* No generic */
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
				extends += "    %s %s (%s);\n  }\n".printf (
						void_return?"":"return", cname, call_args);
			}
			extends += clears;
		}
		//}
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;

		classname = "";
		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);
/*
		if (pkgmode && sr.file.filename.index_of (pkgname) == -1)
			return;
*/
		foreach (var f in ns.get_fields ())
			walk_field (f);
		foreach (var e in ns.get_enums ())
			walk_enum (e);
		foreach (var c in ns.get_structs ()) {
			/* TODO: refactor to walk_struct */
			foreach (var m in c.get_methods ())
				walk_method (m);
			foreach (var f in c.get_fields ())
				walk_field (f);
		}
		foreach (var m in ns.get_methods ())
			walk_method (m);
		var classprefix = ns.name == modulename? ns.name: "";
		foreach (var c in ns.get_classes ())
			walk_class (classprefix, c); //ns.name, c);
		//ns.accept_children (this);
	}

	public override void write (string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (file));
		context.accept (this);
		if (includefiles.length () > 0) {
			stream.printf ("extern \"C\" {\n");
			foreach (var inc in includefiles)
				stream.printf ("#include <%s>\n", inc);
			stream.printf ("}\n#include <vector>\n");
		}
		foreach (var inc in includefiles)
			stream.printf ("#include <%s>\n", inc);
/*
		if (vectors != "")
			stream.printf ("namespace std {\n%s}\n", vectors);
*/
		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", extends);
	}
}
