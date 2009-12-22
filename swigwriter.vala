using Vala;

public class SwigWriter : CodeVisitor {
	private Scope current_scope; // to be removed ?
	private CodeContext context;
	private FileStream stream;
	public string[] files;
	public GLib.List<string> includefiles;
	public GLib.List<Method> methods;

	public SwigWriter () {
		print ("SwigWriter: initialized\n");
	}

	public override void visit_source_file (SourceFile source) {
		// long form for if (source.filename in files) { ...
		foreach (var file in files) {
			if (file == source.filename) {
				print ("  Source file: %s\n", source.filename);
				source.accept_children (this);
				break;
			}
		}
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
				includefiles.append (foo);
		}
	}

	public void display_cmethod (Method m) {
		print ("    %s: %s\n", 
			m.is_private_symbol ()? "Private": "Public", 
			m.get_cprefix ());
			//m.get_real_cname ());
			//m.get_finish_real_cname ()); // nonabstract/nonvirtual method / coroutine
		print ("       ret: %s\n", m.return_type.to_string ());
		foreach (var foo in m.get_parameters ()) {
			print ("     * arg:  %s\n", foo.name);
			DataType? bar = foo.parameter_type;
			if (bar != null) {
				print ("      type: %s\n", bar.get_cname ());
			}
			//if (bar != null)
			//	print ("      type: %s\n", bar.to_string ());
		}
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name != null)
			print ("  Namespace: %s\n", ns.name);
		if (ns.name != "Radare")
			return;
		process_includes (ns);
		// Namespace has methods to walk everything
		foreach (var e in ns.get_enums ()) {
			print ("enum: %s\n", e.get_cname ());
			foreach (var v in e.get_values ()) {
				print ("   - %s\n", v.name);
			}
		}
		foreach (var m in ns.get_methods ()) {
			print ("method: %s\n", m.get_cname ());
			display_cmethod (m);
		}
		foreach (var c in ns.get_classes ()) {
			print ("class: %s (%s)\n", c.name, c.get_cname ());
			foreach (var e in c.get_enums ()) {
				print ("  enum: %s (%s)\n", e.name, e.get_lower_case_cname ());
				foreach (var v in e.get_values ()) {
					print ("     - %s\n", v.name);
				}
			}
			foreach (var m in c.get_methods ()) {
				display_cmethod (m);
				print ("  --method: %s\n", m.get_cname ());
			}
		}

		foreach (var c in ns.get_structs ()) {
			print ("struct: %s\n", c.get_cname ());
			foreach (var m in c.get_methods ()) {
				display_cmethod (m);
				print ("  method: %s\n", m.get_cname ());
			}
		}
		// DO NOT FOLLOW NAMESPACES ONLY SCAN PROVIDED ONES
		ns.accept_children (this);
	}

/*
	public override void visit_interface (Interface iface) {
		print ("  Interface: %s\n", iface.name);
//		iface.accept_children (this);
	}

	public override void visit_enum (Enum enu) {
		print ("  Enumeration: %s\n", enu.get_cname ());
		enu.accept_children (this);
	}

	public override void visit_enum_value (Vala.EnumValue enu) {
		print ("     - %s\n", enu.get_cname ());
		enu.accept_children (this);
	}

	public override void visit_delegate (Delegate del) {
		print ("  Delegate: %s\n", del.get_cname ());
	}

	public override void visit_class (Class cl) {
		var classname = cl.get_cname ();
		print ("  Class name: '%s'\n", classname);
		print ("%%extend %s\n", classname);
		cl.accept_children (this);
	}

	public override void visit_method (Method m) {
		print ("    %s: %s\n", 
			m.is_private_symbol ()? "Private": "Public", 
			m.get_cprefix ());
			//m.get_real_cname ());
			//m.get_finish_real_cname ()); // nonabstract/nonvirtual method / coroutine
		print ("      ret: %s\n", m.return_type.to_string ());
		foreach (var foo in m.get_parameters ()) {
			print ("    - arg:  %s\n", foo.name);
			DataType? bar = foo.parameter_type;
			if (bar != null) {
				if (bar.data_type != null)
					print ("      type: %s\n", bar.data_type.to_string ());
				else print ("      type: %s ???\n", bar.to_string ());
			}
			//if (bar != null)
			//	print ("      type: %s\n", bar.to_string ());
		}
		m.accept_children (this);
	}

	public override void visit_member (Member m) {
		print ("  = %s\n", m.name);
		// TODO do it everywhere
		process_includes (m);
		//print ("    type: %s\n", m.get_full_name ());
	}

	public override void visit_field (Field f) {
	// same as visit_member
	//	print ("  Field: %s\n", f.name);
	}

	public override void visit_creation_method (CreationMethod m) {
		print ("    CreationMethod: %s\n", m.get_cname ());
	}

	public override void visit_constructor (Constructor c) {
		print ("  Constructor: %s\n", c.name);
	}

	public override void visit_destructor (Destructor d) {
		print ("  Destructor: %s\n", d.name);
	}

	public override void visit_block (Block b) {
		print ("  Block: %s\n", b.name);
	}
*/

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		this.context = context;
		this.includefiles = new GLib.List<string>();

		print ("(\n");

		current_scope = context.root.scope;
		context.accept (this);
		current_scope = null;

		print ("%{\n");
		foreach (var inc in includefiles)
			print ("#include <%s>\n", inc);
		print ("%}\n");

		print (")\n");

		this.stream = null;
	}
}
