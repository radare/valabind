/* Copyleft 2012 -- pancake // eddyb */

using Vala;

public class NodeFFIWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public string[] files;
	private string bind;
	private string modulename;
	public GLib.List<string> includefiles;
	private Namespace nspace;
	private string ?nspace_pfx;

	public NodeFFIWriter (string name) {
		bind = "";
		modulename = name;
		includefiles = new GLib.List<string> ();
	}
	
	private bool use_namespace (Namespace ns) {
		// FIXME implement cmd args to select namespace
		return ns.get_full_name () == "Radare";
	}

	private string get_alias (string name) {
		switch (name) {
			case "delete":
				return "_delete";
			case "continue":
				return "_continue";
		}
		return name;
	}

	/*
	private string get_typeFromC (DataType ?_type, string value) {
		// TODO: DRY (don't repeat yourself) ret/args generation.
		var _delegate = _type as DelegateType;
		if (_delegate != null) {
			var ret = type_name (_delegate.get_return_type ());
			string args = "";
			foreach (var param in _delegate.get_parameters ()) {
				if (args != "") args += ", ";
				args += type_name (param.variable_type);
			}
			return "ffi.ForeignFunction(%s, %s, [%s])".printf (value, ret, args);
		}
	}

	private string get_typeToC (DataType ?type, string value) {
		// TODO: DRY (don't repeat yourself) ret/args generation.
		var _delegate = type as DelegateType;
		if (_delegate != null) {
			var ret = type_name (_delegate.get_return_type ());
			
			string args = "";
			foreach (var param in _delegate.get_parameters ()) {
				if (args != "") args += ", ";
				args += type_name (param.variable_type);
			}
			return "ffi.Callback(%s, [%s], void(0), %s)".printf (ret, args, value);
		}
	}*/

	private string type_name (DataType type, bool ignoreRef=false) {
		if (type == null) {
			ValabindCompiler.warning ("Cannot resolve type");
			return "throw TypeError('Unresolved type')";
		}
		if (type is EnumValueType)
			return "types.int";
		
		if (type is GenericType)
			return "$"+type.to_qualified_string ();
		
		if (type is DelegateType)
			return "ptrT(types.void)/*FIXME Delegate*/";
		
		if (type is PointerType)
			return "ptrT("+type_name ((type as PointerType).base_type, true)+")";
		
		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type);
			if (!array.fixed_length)
				return "ptrT("+element+")";
			return "arrT("+element+", %d)".printf (array.length);
		}
		
		if (!ignoreRef && (type is ReferenceType)) {
			string unref_type = type_name (type, true);
			if (unref_type == "types.CString") // HACK just check for GLib.string instead (how?)
				return unref_type;
			return "refT("+unref_type+")";
		}
		string generic = "";
		foreach (DataType t in type.get_type_arguments ()) {
			if (generic != "")
				generic += ", ";
			generic += type_name (t);
		}
		string _type = type.to_string ();
		
		// HACK find a better way to remove generic type args
		_type = _type.split ("<", 2)[0];
		
		if (nspace_pfx != null)
			_type = _type.replace (nspace_pfx, "");
		
		_type = _type.replace (".", "").replace ("?","").replace (" *", "*");

		switch (_type) {
			case "gconstpointer":
			case "gpointer":
				return "ptrT(types.void)";
			case "gboolean":
				return "types.bool";
			case "gchar":
				return "types.char";
			case "gint":
				return "types.int";
			case "guint":
			case "unsigned int":
				return "types.uint";
			case "glong":
				return "types.long";
			case "ut8":
			case "guint8":
				return "types.uint8";
			case "ut16":
			case "guint16":
				return "types.uint16";
			case "st32":
			case "gint32":
				return "types.int32";
			case "ut32":
			case "guint32":
				return "types.uint32";
			case "st64":
			case "gint64":
				return "types.int64";
			case "ut64":
			case "guint64":
				return "types.uint64";
			case "gfloat":
				return "types.float";
			case "gdouble":
				return "types.double";
			case "string":
				return "types.CString";
		}
		_type = "types."+_type;
		if (generic != "")
			_type += "("+generic+")";
		return _type;
	}

	public void add_includes (Symbol s) {
		foreach (string i in CCodeBaseModule.get_ccode_header_filenames (s).split (",")) {
			bool include = true;
			foreach (string j in includefiles) {
				if (i == j) {
					include = false;
					break;
				}
			}
			if (include)
				includefiles.prepend (i);
		}
	}
	
	public override void visit_enum (Enum e) {
		if (nspace == null) return;
		
		//ValabindCompiler.warning ("> enum "+e.name);
		add_includes (e);
		
		foreach (var v in e.get_values ())
			bind += (bind[bind.length-1] == '{' ? "" : ",")+"\n\t\t$%s: /*FIXME %s*/0".printf (v.name, CCodeBaseModule.get_ccode_name (v));
	}
	
	public override void visit_struct (Struct s) {
		if (nspace == null) return;
		
		ValabindCompiler.warning ("> struct "+s.get_full_name ());
		string name = s.get_full_name ().replace (nspace_pfx, "").replace (".", "");
		
		add_includes (s);
		
		bind += (bind == "" ? "" : ",\n")+"\t%s: function() {return [{".printf (name);
		
		foreach (Field f in s.get_fields ())
			visit_field (f);
		
		bind += (bind[bind.length-1] == '{' ? "" : "\n\t")+"}, {";
			
		foreach (Method m in s.get_methods ())
			visit_method (m);
		
		bind += (bind[bind.length-1] == '{' ? "" : "\n\t")+"}];}";
	}
	
	public override void visit_class (Class c) {
		if (nspace == null) return;
		
		ValabindCompiler.warning ("> class "+c.get_full_name ());
		string name = c.get_full_name ().replace (nspace_pfx, "").replace (".", "");
		
		add_includes (c);
		
		bool has_ctor = false;
		foreach (Method m in c.get_methods ())
			if (m is CreationMethod) {
				has_ctor = true;
				break;
			}
		
		bind += (bind == "" ? "" : ",\n")+"\t%s: function(".printf (name);
		foreach (TypeParameter t in c.get_type_parameters ())
			bind += (bind[bind.length-1] == '(' ? "" : ", ")+"$"+t.name;
		bind += ") {return [{";
		
		foreach (Field f in c.get_fields ())
			visit_field (f);
		
		bind += (bind[bind.length-1] == '{' ? "" : "\n\t")+"}, {";

		foreach (Enum e in c.get_enums ())
			visit_enum (e);
		
		string? freefun = CCodeBaseModule.get_ccode_unref_function (c);
		if (freefun != null && freefun != "")
			bind += (bind[bind.length-1] == '{' ? "" : ",")+"\n\t\tdelete: ['%s', types.void, [refT(types.%s)]]".printf (freefun, name);
		else if (has_ctor)
			bind += (bind[bind.length-1] == '{' ? "" : ",")+"\n\t\tdelete: defaults.dtor";
		
		foreach (Method m in c.get_methods ())
			visit_method (m);
		
		bind += (bind[bind.length-1] == '{' ? "" : "\n\t")+"}];}";
		
		foreach (Struct s in c.get_structs ())
			visit_struct (s);
		
		foreach (Class k in c.get_classes ())
			visit_class (k);
		
		//ValabindCompiler.warning ("< class "+c.name);
	}
	
	public override void visit_field (Field f) {
		if (nspace == null) return;
		
		bind += (bind[bind.length-1] == '{' ? "" : ",")+"\n\t\t%s: %s".printf (f.name, type_name (f.variable_type));
	}
	
	public override void visit_method (Method m) {
		if (nspace == null) return;
		
		//ValabindCompiler.warning ("> method "+m.name);
		if (m.is_private_symbol () || m.name == "cast")
			return;

		add_includes (m);
		string cname = CCodeBaseModule.get_ccode_name (m), alias = get_alias (m.name);
		var parent = m.parent_symbol;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0, is_constructor = (m is CreationMethod), parent_is_class = parent is Class || parent is Struct;
		
		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();
		
		if (parent_is_class && is_static)
			alias = "$"+alias;
		
		DataType this_type = m.this_parameter == null ? null : m.this_parameter.variable_type;
		string func = "\n\t\t";
		if (is_constructor) {
			func += "$constructor: ['%s', %s, [".printf (cname, type_name (this_type));
		} else {
			func += "%s: ['%s', %s, [".printf (alias, cname, type_name (m.return_type));
			if (this_type != null)
				func += type_name (this_type);
		}
		
		bool variadic = false;
		foreach (Vala.Parameter param in m.get_parameters ()) {
			if (param.ellipsis) {
				variadic = true;
				continue;
			}
			func += (func[func.length-1] == '[' ? "" : ", ")+type_name (param.variable_type);
		}
		func += variadic ? "], 'variadic']" : "]]";
		
		bind += (bind[bind.length-1] == '{' ? "" : ",")+func;
		if (parent_is_class && alias == "iterator")
			bind += ",\n\t\tforEach: defaults.forEach";
	}

	public override void visit_namespace (Namespace ns) {
		string name = ns.get_full_name ();
		bool use = use_namespace (ns);
		if (use) {
			nspace = ns;
			nspace_pfx = name+".";
		}
		if (nspace != null) {
			ValabindCompiler.warning ("> ns "+name);
			add_includes (ns);
		}
		
		foreach (Namespace n in ns.get_namespaces ())
			visit_namespace (n);
		
		if (nspace != null && nspace != ns) {
			bind += (bind == "" ? "" : ",\n")+"\t%s: function() {return {".printf (name.replace (nspace_pfx, "").replace (".", ""));
		
			foreach (Enum e in ns.get_enums ())
				visit_enum (e);
			
			foreach (Method m in ns.get_methods ())
				visit_method (m);
			
			bind += (bind[bind.length-1] == '{' ? "" : "\n\t")+"};}";
		}
		
		foreach (Struct s in ns.get_structs ())
			visit_struct (s);
		
		foreach (Class c in ns.get_classes ())
			visit_class (c);
		
		if (nspace != null)
			ValabindCompiler.warning ("< ns "+name);
		if (use) {
			nspace = null;
			nspace_pfx = null;
		}
	}

	public void write_file (CodeContext context, string filename) {
		var stream = FileStream.open (filename, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (filename));
		context.root.accept (this);
		//BEGIN Output
		stream.puts (("
/* DO NOT EDIT. Automatically generated by valabind from "+modulename+" */

var ffi = require('ffi'), ref = require('ref'), Struct = require('ref-struct');
var lib = new ffi.DynamicLibrary('lib"+modulename+"'+ffi.LIB_EXT);
var types = {};

for(var i in ffi.types)
	types[i] = ffi.types[i];

// HACK ref forward-compatibility
types.CString = types.CString || types.Utf8String;

function staticCString(N) {
	var r = Object.create(types.char);
	r.name = r.$name = 'char['+N+']';
	r.size *= N;
	r.get = function get(buf, offset) {
		if(buf.isNull())
			return null;
		// TODO enforce maxLength of N
		return buf.readCString(offset);
	};
	r.set = function set(buf, offset, val) {
		// TODO enforce maxLength of N
		return buf.writeCString(val, offset);
	};
	return r;
}

function Tname(T) {
	return T.$name || T.name;
}

function ptrT(T) {
	T = ref.coerceType(T);
	if(T == types.char)
		return types.CString;
	var i = ptrT.cache.indexOf(T), n;
	return i === -1 ? (n = Tname(T), T = ptrT.cacheTo[ptrT.cache.push(T)-1] = ref.refType(T), T.name = T.$name = n+'*', T) : ptrT.cacheTo[i];
}
ptrT.cache = [], ptrT.cacheTo = [];

function refT(T) {
	T = ref.coerceType(T);
	var i = refT.cache.indexOf(T);
	if(i !== -1)
		return refT.cacheTo[i];
	var p = ptrT(T), r = refT.cacheTo[refT.cache.push(T)-1] = Object.create(p);
	r.indirection = 1;
	r.name = r.$name = Tname(T)+'&';
	r.ffi_type = ffi.FFI_TYPES.pointer;
	r.get = function get(buf, offset) {
		buf = ref.get(buf, offset, p);
		if(buf.isNull())
			return null;
		return buf.deref();
	};
	r.set = function set(buf, offset, val) {
		return ref.set(buf, offset, ref.ref(val), p);
	};
	return r;
}
refT.cache = [], refT.cacheTo = [];

function arrT(T, N) {
	T = ref.coerceType(T);
	if(T == types.char)
		return staticCString(N);
	var r = Object.create(T);
	r.size *= N;
	r.name = r.$name = Tname(T)+'['+N+']';
	function ArrayType(pointer, base) {
		this._pointer = pointer;
		this._base = base;
	}
	ArrayType.prototype = [];
	for(var i = 0; i < N; i++)
		Object.defineProperty(ArrayType.prototype, i, {
			get: function get() {
				return ref.get(this._pointer, this._base+T.size*i, T);
			},
			set: function set(val) {
				return ref.set(this._pointer, this._base+T.size*i, val, T);
			},
			enumerable: true
		});
	r.get = function get(buf, offset) {
		return new ArrayType(buf, offset);
	};
	r.set = function set(buf, offset, val) {
		for(var i in val) {
			if(isNaN(i = +i) || i >= N)
				continue;
			ref.set(buf, offset+T.size*i, val[i], T);
		}
	};
	return r;
}

var defaults = {
	dtor: function dtor() {
		this.free && this.free();
	},
	forEach: function forEach(callback, thisArg) {
		if({}.toString.call(callback) != '[object Function]')
			throw new TypeError(callback + ' is not a function');

		for(var T = thisArg || T, iter = this.iterator(); iter; iter = iter.get_next())
			callback.call(T, iter.get_data(), iter, this);
	}
};

function bindings(s) {
	function method(name, ret, args, static, more) {
		var f = (more == 'variadic' ? ffi.VariadicForeignFunction : ffi.ForeignFunction)(lib.get(name), ret, args);
		if(static)
			return f;
		// HACK refT#set doesn't trigger by itself.
		if(args[0] && args[0].ffi_type === ffi.FFI_TYPES.pointer)
			return function() {
				[].unshift.call(arguments, this._pointer);
				return f.apply(null, arguments);
			};
		return function() {
			[].unshift.call(arguments, this);
			return f.apply(null, arguments);
		};
	}
	
	function defineMethod(className, n, m) {
		var static = !className || n[0] === '$';
		if(Array.isArray(m))
			m = method(m[0], m[1], m[2], static, m[3]);
		static && (n = n.slice(1));
		if(n == 'constructor')
			exports[className] = m, exports[className].$type = types[className];
		else if(static)
			className ? exports[className][n] = m : exports[n] = m;
		else
			types[className].prototype[n] = m;
	}
	
	function makeGeneric(G, n) {
		var cache = [], cacheTo = [];
		return function() {
			var l = arguments.length, args = [], c;
			
			// Coerce all type arguments.
			for(var i = 0; i < l; i++)
				args[i] = ref.coerceType(arguments[i].$type || arguments[i]);
			
			// Look in the cache, if the generic was already built.
			for(var i = 0; i < cache.length; i++) {
				if((c = cache[i]).length !== l)
					continue;
				for(var j = 0; j < l && c[j] === args[j]; j++);
				if(j === l)
					return cacheTo[i];
			}
			
			// Create the new generic.
			var generic = cacheTo[cache.push(args)-1] = Struct(), g = G.apply(null, args);
			generic.$name = n+'<'+args.map(function(T) {return T.name;}).join(', ')+'>';

			// Define all the generic's propoerties.
			for(var i in g[0])
				generic.defineProperty(i, g[0][i]);
			
			// Insert all the generic's methods.
			if(g[1])
				for(var i in g[1]) {
					var m = g[1][i];
					if(Array.isArray(m))
						m = method(m[0], m[1], m[2], false, m[3]);
					generic.prototype[i] = m;
				}
			return generic;
		};
	}
	for(var i in s) {
		if(s[i].length)
			types[i] = makeGeneric(s[i], i);
		else
			exports[i] = types[i] = Struct(), types[i].$name = i;
	}
	for(var i in s) {
		if(s[i].length) {
			// insert constructor
			delete s[i];
			continue;
		}
		s[i] = s[i]();
		if(Array.isArray(s[i]))
			for(var j in s[i][0])
				types[i].defineProperty(j, s[i][0][j]);
	}
	for(var i in s) {
		if(Array.isArray(s[i]))
			for(var j in s[i][1])
				defineMethod(i, j, s[i][1][j]);
		else {
			exports[i] = {};
			for(var j in s[i]) {
				var m = s[i][j];
				if(Array.isArray(m))
					m = method(m[0], m[1], m[2], false, m[3]);
				exports[i][j] = m;
			}
		}
	}
}
bindings({\n"+bind+"\n});\n"
		).replace("\t", "    "));
		//END Output
	}
}
