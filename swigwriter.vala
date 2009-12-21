using Vala;

public class SwigWriter : CodeVisitor {
	private Scope current_scope; // to be removed ?
	private CodeContext context;
	private FileStream stream;
	public string[] files;

	public SwigWriter () {
		print ("SwigWriter: initialized\n");
	}

	public override void visit_source_file (SourceFile source) {
		foreach (var file in files) {
			if (file == source.filename) {
				print ("  Source file: %s\n", source.filename);
				source.accept_children (this);
				break;
			}
		}
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name != null)
			print ("  Namespace: %s\n", ns.name);
//		ns.accept_children (this);
	}

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
		print ("  Class name: %s\n", cl.get_cname ());
		cl.accept_children (this);
	}

	public override void visit_method (Method m) {
		print ("    %s : %s\n", 
			m.is_private_symbol ()? "Private": "Public", 
			m.get_real_cname ());
		print ("      ret: %s\n", m.return_type.to_string ());
		foreach (var foo in m.get_parameters ()) {
			print ("    - arg:  %s\n", foo.name);
			DataType? bar = foo.parameter_type;
			if (bar != null)
				print ("      type: %s\n", bar.to_string ());
		}
		m.accept_children (this);
	}

	public override void visit_member (Member m) {
		print ("  Member: %s\n", m.name);
	}

	public override void visit_field (Field f) {
		print ("  Field: %s\n", f.name);
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

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		this.context = context;

		print ("(\n");

		current_scope = context.root.scope;
		context.accept (this);
		current_scope = null;

		print (")\n");

		this.stream = null;
	}
}
