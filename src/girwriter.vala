/* Copyright 2011-2019 -- pancake */

using Vala;

public class GirWriter : ValabindWriter {
	public GLib.List<string> includefiles = new GLib.List<string> ();
	public GLib.List<Method> methods;
	string classname = "";
	string classcname;
	string externs = "";
	string statics = "";
	string extends = "";
	string enums = "";
	string nspace;

	public GirWriter () {
	}

	public override string get_filename (string base_name) {
		return base_name+".gir";
	}

	string get_alias (string name) {
		string oname = name;
		switch (name) {
/*
		case "use":
			return "_use";
*/
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
		case "continue":
			name = "cont";
			break;
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
		if (type.has_suffix ("[]?"))
			return get_ctype (type.substring (0, type.length - 3)) + "*";
		if (type.has_suffix ("[]"))
			return get_ctype (type.substring (0, type.length - 2)) + "*";
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
		type = type.replace ("?", "");

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
			return "char **";
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
			return "char *";
			//return "char *"; // ???
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
			return "gboolean";
		case "RFList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
		case "RList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
		case "SdbList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
		}
		return type;
	}

	string type_name_for_gir (DataType type) {
		if (type is ArrayType)
			return ((ArrayType) type).element_type.to_string ();
		return type.to_string ();
	}

	string get_array_attrs (CodeNode? node) {
		string attrs = "";
		if (node == null)
			return attrs;
		if (Vala.get_ccode_array_length (node))
			attrs += " length=\"%d\"".printf ((int) Vala.get_ccode_array_length_pos (node));
		if (Vala.get_ccode_array_null_terminated (node))
			attrs += " zero-terminated=\"1\"";
		return attrs;
	}

	string render_type (CodeNode? node, DataType type) {
		var type_name = type_name_for_gir (type);
		var ctype = get_type_ctype (type);
		if (type is ArrayType) {
			var attrs = get_array_attrs (node);
			var array = (ArrayType) type;
			var element = array.element_type;
			var element_name = girtype (type_name_for_gir (element));
			var element_ctype = get_type_ctype (element);
			return "      <array%s c:type=\"%s\">\n        <type name=\"%s\" c:type=\"%s\"/>\n      </array>\n".printf (
				attrs, ctype, element_name, element_ctype);
		}
		return "      <type name=\"%s\" c:type=\"%s\"/>\n".printf (
			girtype (type_name), ctype);
	}

	string get_type_ctype (DataType type) {
		string? type_code = null;
		if (type.type_symbol != null)
			type_code = Vala.get_ccode_name (type.type_symbol);
		if (type_code == null || type_code == "")
			type_code = Vala.get_ccode_name (type);
		if (type_code == null || type_code == "")
			type_code = type.to_string ();
		if (type is ReferenceType && type_code[type_code.length - 1] != '*')
			type_code += "*";
		return get_ctype (type_code);
	}

	bool allow_none (DataType? type) {
		return type != null && type.nullable;
	}

	bool supports_ownership_transfer (DataType type) {
		if (type.to_string () == "void")
			return false;
		if (type is ReferenceType || type is ArrayType || type is PointerType || type is DelegateType || type is GenericType)
			return true;
		string name = type.to_string ();
		return name == "string" || name == "string?";
	}

	string transfer_ownership_for_return (Method m) {
		if (m is CreationMethod)
			return "full";
		if (!supports_ownership_transfer (m.return_type))
			return "none";
		if (m.return_type.floating_reference || m.returns_floating_reference)
			return "floating";
		if (m.return_type.value_owned)
			return "full";
		return "none";
	}

	string transfer_ownership_for_param (Vala.Parameter p) {
		var type = p.variable_type;
		if (type == null)
			return "none";
		if (!supports_ownership_transfer (type))
			return "none";
		return (type.value_owned || type.floating_reference) ? "full" : "none";
	}

	string? enum_value_text (Expression? expr, ref int64 next_value) {
		if (expr == null) {
			var value = next_value.to_string ();
			next_value++;
			return value;
		}

		if (expr is IntegerLiteral) {
			var value = ((IntegerLiteral) expr).value;
			next_value = int64.parse (value, 0) + 1;
			return value;
		}

		if (expr is UnaryExpression) {
			var unary = (UnaryExpression) expr;
			if (unary.operator == UnaryOperator.MINUS && unary.inner is IntegerLiteral) {
				var value = "-" + ((IntegerLiteral) unary.inner).value;
				next_value = int64.parse (value, 0) + 1;
				return value;
			}
		}

		return null;
	}

	static string girtype(string ret) {
		switch (ret) {
		case "int[]":
			return "gpointer"; // XXX
		case "string?":
		case "string":
		case "char*":
		case "char *":
		case "const char*":
			ret = "utf8";
			break;
		case "uint":
		case "uint32":
		case "unsigned int":
			ret = "guint";
			break;
		case "int":
		case "int32":
			ret = "gint";
			break;
		case "unsigned long long":
		case "uint64":
			ret = "guint64";
			break;
		case "void*":
		case "unsigned char*":
		case "uint8*":
			ret = "gpointer";
			break;
		case "bool":
			ret = "gboolean";
			break;
		}
		if (ret[ret.length-1] == '*')
			return "gpointer";
		return ret;
	}

	bool is_target_file (string path) {
		// FIXME implement the new method with use_namespace instead
		foreach (var file in source_files)
			if (file == path)
				return true;
		return false;
	}

	public void walk_constant (Constant f) {
		var cname = Vala.get_ccode_name (f);
		var cvalue = (f.value != null) ? f.value.to_string () : "0";
		var ctype = get_ctype (f.type_reference.to_string ());
		var gtype = girtype (f.type_reference.to_string ());
		extends += "<constant name=\""+cname+"\" value=\""+cvalue+"\">\n";
		extends += "  <type name=\""+gtype+"\" c:type=\""+ctype+"\"/>\n";
		extends += "</constant>\n";
		//extends += "static const char *"+f.name+" = "+cname+";\n";
	}

	public override void visit_source_file (SourceFile source) {
		if (is_target_file (source.filename))
			source.accept_children (this);
	}

	public void process_includes (Symbol s) {
		foreach (var foo in Vala.get_ccode_header_filenames (s).split (",")) {
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
		var name = Vala.get_ccode_name (f);
		var type = f.variable_type;
		externs += "    <field name=\""+name+"\"";
		if (allow_none (type))
			externs += " allow-none=\"1\"";
		externs += ">\n";
		externs += render_type (f, type);
		externs += "    </field>\n";
	}

	public void walk_struct (string pfx, Struct s) {
		var name = s.name;
		classcname = Vala.get_ccode_name (s);
		externs += "  <record name=\""+name+"\" c:type=\""+Vala.get_ccode_name (s)+"\">\n";
		/* TODO: refactor to walk_struct */
		foreach (var m in s.get_methods ())
			walk_method (m);
		foreach (var f in s.get_fields ())
			walk_field (f);
		externs += "  </record>\n";
	}

	public void walk_class (string pfx, Class c) {
		foreach (var k in c.get_classes ())
			walk_class (c.name, k);
		classname = pfx+c.name;
		classcname = Vala.get_ccode_name (c);
		process_includes (c);
		if (context.profile == Profile.GOBJECT)
			classname = "%s%s".printf (nspace, classname);
		externs += "  <record name=\""+classname+"\" c:type=\""+classcname+"\">\n"; // TODO: parent="" type-name="" get-type=""
// TODO: print ("PARENT FOR "+classname+" IS: "+c.parent_node.type_name+"\n");
		// parent=\"\"
		foreach (var e in c.get_enums ())
			walk_enum (e);
		foreach (var f in c.get_fields ())
			walk_field (f);
/*
		if (c.is_reference_counting ()) {
			string? freefun = c.get_unref_function ();
			if (freefun != null)
				extends += "  ~%s%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
		} else {
			string? freefun = c.get_free_function ();
			if (freefun != null)
				extends += "  ~%s%s() {\n    %s (self);\n  }\n".printf (modulename, classname, freefun);
		}
*/
		foreach (var m in c.get_methods ())
			walk_method (m);
		externs += "  </record>\n";
		classname = "";
	}

	public void walk_enum (Vala.Enum e) {
		var enumname = (classname != "") ? classname + e.name : e.name;
		int64 next_value = 0;
		bool ok = true;
		bool has_values = false;
		var tag = e.is_flags ? "bitfield" : "enumeration";
		var tmp = "  <%s name=\"%s\" c:type=\"%s\">\n".printf (tag, enumname, Vala.get_ccode_name (e));

		foreach (var v in e.get_values ()) {
			has_values = true;
			var value = enum_value_text (v.value, ref next_value);
			if (value == null) {
				ok = false;
				break;
			}
			var nick = v.nick;
			if (nick == null || nick == "")
				nick = v.name.down ();
			tmp += "    <member name=\"%s\" value=\"%s\" c:identifier=\"%s\" glib:nick=\"%s\" glib:name=\"%s\"/>\n".printf (
				nick, value, Vala.get_ccode_name (v), nick, Vala.get_ccode_name (v));
		}

		if (!ok) {
			warning ("Skipping enum %s because its values are not simple literals".printf (e.get_full_name ()));
			return;
		}

		if (!has_values) {
			warning ("Skipping enum %s because it has no members".printf (e.get_full_name ()));
			return;
		}

		tmp += "  </%s>\n".printf (tag);
		enums = tmp + "\n" + enums;
	}

	inline bool is_generic(string type) {
		return (type.index_of ("<") != -1 && type.index_of (">") != -1);
	}

	public void walk_method (Method m) {
		//bool first = true;
		string cname = Vala.get_ccode_name (m);
		string alias = get_alias (m.name);
		string ret, vret;
		bool void_return;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		ret = vret = m.return_type.to_string ();
		if (is_generic (ret)) ret = get_ctype (vret);
		else ret = get_ctype (Vala.get_ccode_name (m.return_type));
		if (ret == null)
			error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");

		if (m.is_private_symbol ())
			return;

		string type = is_static?"function":"method";
		if (classname != "" && !is_static)
			type = "method";
		if (is_constructor) {
			type = "constructor";
			alias = "new";
			void_return = false;
			ret = nspace+"."+classname;
		}
		//externs += "<"+type+" name=\""+alias+"\" c:identifier=\""+cname+"\">\n";
		externs += "<"+type+" name=\""+alias+"\" c:identifier=\""+cname+"\">\n";
			//externs += "  <return-type type=\"void\"/>\n";
		externs += "  <return-value transfer-ownership=\""+transfer_ownership_for_return (m)+"\"";
		if (allow_none (m.return_type))
			externs += " allow-none=\"1\"";
		externs += ">\n";
		if (!void_return) {
			if (is_constructor)
				externs += "    <type name=\""+classname+"\" c:type=\""+classcname+"*\"/>\n";
			else
				externs += render_type (m, m.return_type);
		} else externs += "    <type name=\"none\"/>\n";
		externs += "  </return-value>\n";

		var parameters = m.get_parameters ();
		if (parameters.size>0 || (!is_static && !is_constructor && m.this_parameter != null)) {
			externs += "  <parameters>\n";
			if (!is_static && !is_constructor && m.this_parameter != null) {
				externs += "    <instance-parameter name=\""+m.this_parameter.name+"\" transfer-ownership=\"none\"";
				if (allow_none (m.this_parameter.variable_type))
					externs += " allow-none=\"1\"";
				externs += ">\n";
				externs += "      <type name=\"%s\" c:type=\"%s*\"/>\n".printf (
					type_name_for_gir (m.this_parameter.variable_type), classcname);
				externs += "    </instance-parameter>\n";
			}
			foreach (var foo in parameters) {
				string arg_name = foo.name;
				DataType? bar = foo.variable_type;
				if (bar == null)
					continue;
				externs += "    <parameter name=\""+arg_name+"\" transfer-ownership=\""+transfer_ownership_for_param (foo)+"\"";
				if (allow_none (bar))
					externs += " allow-none=\"1\"";
				externs += ">\n";
				externs += render_type (foo, bar);
				externs += "    </parameter>\n";
			}
			externs += "  </parameters>\n";
		}
		externs += "</"+type+">\n"; //function>\n";
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;

		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);
//externs += "<namespace version=\"1.0\" name=\""+nspace+"\">\n";
		//if (pkgmode && sr.file.filename.index_of (pkgname) == -1)
		//	return;
		foreach (var f in ns.get_constants ())
			walk_constant (f);
		foreach (var f in ns.get_fields ())
			walk_field (f);
		foreach (var e in ns.get_enums ())
			walk_enum (e);
		foreach (var s in ns.get_structs ())
			walk_struct ("", s);
		foreach (var m in ns.get_methods ())
			walk_method (m);
		foreach (var c in ns.get_classes ())
			walk_class ("", c);
		//ns.accept_children (this);
//externs += "</namespace>\n";
	}

	public override void write(string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (file));
		context.accept (this);
		stream.printf ("<?xml version=\"1.0\"?>\n");
		stream.printf ("<!-- automatically generated with valabind -->\n");
		stream.printf ("<!-- To compile: g-ir-compiler foo.gir > foo.typelib -->\n");
		stream.printf ("<repository version=\"1.2\"\n"+
			"	xmlns=\"http://www.gtk.org/introspection/core/1.0\"\n"+
			"	xmlns:c=\"http://www.gtk.org/introspection/c/1.0\"\n"+
			"	xmlns:glib=\"http://www.gtk.org/introspection/glib/1.0\">\n");
		stream.printf ("  <package name=\""+modulename+"-1.0\"/>\n");
		if (includefiles.length () > 0)
			foreach (var inc in includefiles)
				stream.printf ("  <c:include name=\"%s\"/>\n", inc);
		stream.printf ("  <namespace version=\"1.0\" name=\""+modulename+"\">\n");

		stream.printf ("%s\n", enums);
		stream.printf ("%s\n", externs);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", extends);

		stream.printf ("  </namespace>\n");
		stream.printf ("</repository>\n");
	}
}
