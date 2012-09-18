/* Copyleft 2012 -- pancake // eddyb */

using Vala;

public class NodeFFIWriter : ValabindWriter {
	GLib.List<string> includefiles = new GLib.List<string> ();
	string ?ns_pfx;
	string bind = "";
	string enum_fmt = "";
	string enum_vals = "";

	public NodeFFIWriter () {
	}

	public override string get_filename (string base_name) {
		return base_name+".js";
	}

	void add_includes (Symbol s) {
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

	string sep (string str, string separator) {
		if (str.length == 0)
			return str;
		char last = str[str.length-1];
		if (last != '(' && last != '[' && last != '{')
			return str+separator;
		return str;
	}

	string type_name (DataType type, bool ignoreRef=false) {
		if (type == null) {
			warning ("Cannot resolve type");
			return "throw TypeError('Unresolved type')";
		}

		if (type is EnumValueType)
			return "_.int";

		if (type is GenericType)
			return type.to_qualified_string ();

		if (type is DelegateType) {
			DelegateType _delegate = type as DelegateType;
			string ret = type_name (_delegate.get_return_type ()), args = "";
			foreach (var param in _delegate.get_parameters ())
				args = sep (args, ", ")+type_name (param.variable_type);
			return "_.delegate(%s, [%s])".printf (ret, args);
		}

		if (type is PointerType)
			return "_.ptr("+type_name ((type as PointerType).base_type, true)+")";

		if (type is ArrayType) {
			ArrayType array = type as ArrayType;
			string element = type_name (array.element_type);
			if (!array.fixed_length)
				return "_.ptr("+element+")";
			return "_.array("+element+", %d)".printf (array.length);
		}

		if (!ignoreRef && (type is ReferenceType)) {
			string unref_type = type_name (type, true);
			// HACK just check for the string class instead (how?)
			if (unref_type == "_.CString")
				return unref_type;
			return "_.ref("+unref_type+")";
		}

		string generic = "";
		foreach (DataType t in type.get_type_arguments ())
			generic = sep (generic, ", ") + type_name (t);

		string _type = type.to_string ();

		// HACK find a better way to remove generic type args
		_type = _type.split ("<", 2)[0];

		_type = _type.replace (ns_pfx, "").replace (".", "");
		_type = _type.replace ("?","");
		_type = _type.replace ("unsigned ", "u");

		switch (_type) {
			case "gconstpointer":
			case "gpointer":
				return "_.ptr(_.void)";
			case "gboolean":
				return "_.bool";
			case "gchar":
				return "_.char";
			case "gint":
				return "_.int";
			case "guint":
				return "_.uint";
			case "glong":
				return "_.long";
			case "ut8":
			case "guint8":
				return "_.uint8";
			case "ut16":
			case "guint16":
				return "_.uint16";
			case "st32":
			case "gint32":
				return "_.int32";
			case "ut32":
			case "guint32":
				return "_.uint32";
			case "st64":
			case "gint64":
				return "_.int64";
			case "ut64":
			case "guint64":
				return "_.uint64";
			case "gfloat":
				return "_.float";
			case "gdouble":
				return "_.double";
			case "string":
				return "_.CString";
		}
		_type = "_."+_type;
		if (generic != "")
			_type += "("+generic+")";
		return _type;
	}

	new void visit_enum (Vala.Enum e, string pfx="") {
		add_includes (e);

		notice (">\x1b[1menum\x1b[0m "+e.get_full_name ());

		if (pfx == "")
			enum_fmt += "exports.%s = {}/*types.Enum*/;\\n".printf (e.name);
		else
			bind = sep (bind, ",")+"\n\t\t$%s: {}/*types.Enum*/".printf (e.name);
		foreach (var v in e.get_values ()) {
			enum_fmt += "exports.%s%s.%s = %%d;\\n".printf (pfx, e.name, v.name);
			enum_vals += ","+CCodeBaseModule.get_ccode_name (v);
		}
	}

	public override void visit_struct (Struct s) {
		add_includes (s);

		notice (">\x1b[1mstruct\x1b[0m "+s.get_full_name ());
		string name = s.get_full_name ().replace (ns_pfx, "").replace (".", "");

		bind = sep (bind, ",\n")+"\t%s: function() {return [{".printf (name);

		foreach (Field f in s.get_fields ())
			f.accept (this);

		bind = sep (bind, "\n\t")+"}, {";

		// NOTE if m.accept (this) is used, it might try other functions than visit_method
		foreach (Method m in s.get_methods ())
			m.accept (this);

		bind = sep (bind, "\n\t")+"}];}";
	}

	public override void visit_class (Class c) {
		bool is_generic = false;
		add_includes (c);

		notice (">\x1b[1mclass\x1b[0m "+c.get_full_name ());
		string name = c.get_full_name ().replace (ns_pfx, "").replace (".", "");

		bind = sep (bind, ",\n")+"\t%s: function(".printf (name);
		foreach (TypeParameter t in c.get_type_parameters ()) {
			is_generic = true;
			bind = sep (bind, ", ")+t.name;
		}
		bind += ") {return [{";

		foreach (Field f in c.get_fields ())
			f.accept (this);

		bind = sep (bind, "\n\t")+"}, {";

		foreach (Vala.Enum e in c.get_enums ())
			visit_enum (e, name+".");

		// TODO use node-weak to call the free function on GC
		string? freefun = null;
		if (CCodeBaseModule.is_reference_counting (c))
			freefun = CCodeBaseModule.get_ccode_unref_function (c);
		else
			freefun = CCodeBaseModule.get_ccode_free_function (c);
		if (freefun != null && freefun != "") {
			if (is_generic)
				name = name +"(G)";
			bind = sep (bind, ",")+"\n\t\tdelete: ['%s', _.void, [_.ref(_.%s)]]".printf (freefun, name);
		}

		// NOTE if m.accept (this) is used, it might try other functions than visit_method
		foreach (Method m in c.get_methods ())
			visit_method (m);

		bind = sep (bind, "\n\t")+"}];}";

		foreach (Struct s in c.get_structs ())
			s.accept (this);
		foreach (Class k in c.get_classes ())
			k.accept (this);
	}

	public override void visit_field (Field f) {
		bind = sep (bind, ",")+"\n\t\t%s: %s".printf (f.name, type_name (f.variable_type));
	}

	public override void visit_method (Method m) {
		if (m.is_private_symbol () || m.name == "cast")
			return;

		add_includes (m);

		//notice (">\x1b[1mmethod\x1b[0m "+m.get_full_name ());
		var parent = m.parent_symbol;
		string cname = CCodeBaseModule.get_ccode_name (m), name = m.name;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0, is_constructor = (m is CreationMethod);
		bool parent_is_class = parent is Class || parent is Struct;

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		if (parent_is_class && is_static)
			name = "$"+name;

		DataType this_type = m.this_parameter == null ? null : m.this_parameter.variable_type;
		string func = "\n\t\t";
		if (is_constructor) {
			func += "$constructor: ['%s', %s, [".printf (cname, type_name (this_type));
		} else {
			func += "%s: ['%s', %s, [".printf (name, cname, type_name (m.return_type));
			if (this_type != null)
				func += type_name (this_type);
		}

		bool variadic = false;
		foreach (Vala.Parameter param in m.get_parameters ()) {
			// HACK is this the right way to detect variadic functions?
			if (param.ellipsis) {
				variadic = true;
				continue;
			}
			func = sep (func, ", ")+type_name (param.variable_type);
		}
		func += variadic ? "], 'variadic']" : "]]";

		bind = sep (bind, ",")+func;
		if (parent_is_class && name == "iterator")
			bind += ",\n\t\tforEach: defaults.forEach";
	}

	public override void visit_namespace (Namespace ns) {
		string name = ns.get_full_name ();
		bool use = use_namespace (ns);
		if (use)
			ns_pfx = name+".";
		if (ns_pfx != null) {
			notice (">\x1b[1mns\x1b[0m "+name);
			add_includes (ns);
		}

		foreach (Namespace n in ns.get_namespaces ())
			n.accept (this);

		if (ns_pfx != null) {
			if (!use) {
				name = name.replace (ns_pfx, "").replace (".", "");
				bind = sep (bind, ",\n")+"\t$%s: function() {return {".printf (name);

				foreach (Method m in ns.get_methods ())
					m.accept (this);

				foreach (Vala.Enum e in ns.get_enums ())
					visit_enum (e, name+".");

				bind = sep (bind, "\n\t")+"};}";
			} else
				foreach (Vala.Enum e in ns.get_enums ())
					visit_enum (e);

			foreach (Struct s in ns.get_structs ())
				s.accept (this);

			foreach (Class c in ns.get_classes ())
				c.accept (this);
		}

		//if (ns_pfx != null)
		//	notice ("<\x1b[1mns\x1b[0m "+name);
		if (use)
			ns_pfx = null;
	}

	public override void write (string file) {
		var stream = FileStream.open (file, "w");
		if (stream == null)
			error ("Cannot open %s for writing".printf (file));
		context.root.accept (this);
		{stream.puts ("
/* DO NOT EDIT. Automatically generated by valabind from "+modulename+" */

var ffi = require('ffi'), ref = require('ref'), Struct = require('ref-struct');
var lib = new ffi.DynamicLibrary('lib"+modulename+"'+ffi.LIB_EXT);

function Tname(T) {
	return T.hasOwnProperty('$name') ? T.$name : T.name;
}

var types = exports.type = {};

for(var i in ref.types)
	if(i != 'Utf8String') // Try not to trip the deprecated warning.
		types[i] = ref.types[i];

types.staticCString = function staticCString(N) {
	var r = Object.create(types.char);
	r.name = 'char['+N+']';
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
};

var ptrCache = [], ptrCacheTo = [];
types.ptr = function PointerType(T) {
	T = ref.coerceType(T);
	if(T == types.char)
		return types.CString;
	var i = ptrCache.indexOf(T);
	return i === -1 ? ptrCacheTo[ptrCache.push(T)-1] = ref.refType(T) : ptrCacheTo[i];
};

var refCache = [], refCacheTo = [];
types.ref = function ReferenceType(T) {
	T = ref.coerceType(T);
	var i = refCache.indexOf(T);
	if(i !== -1)
		return refCacheTo[i];
	var p = types.ptr(T), r = refCacheTo[refCache.push(T)-1] = Object.create(p);
	r.indirection = 1;
	r.size = ref.sizeof.pointer;
	r.name = Tname(T)+'&';
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
};

types.array = function ArrayType(T, N) {
	T = ref.coerceType(T);
	if(T == types.char)
		return types.staticCString(N);
	var r = Object.create(T);
	r.size *= N;
	r.name = Tname(T)+'['+N+']';
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
};

types.delegate = function DelegateType(ret, args) {
	var p = types.ptr(types.void), r = Object.create(p);
	r.indirection = 1;
	r.name = Tname(ret)+'('+args.map(function(T) {return Tname(T);}).join(', ')+')';
	r.get = function get(buf, offset) {
		buf = ref.get(buf, offset, p);
		if(buf.isNull())
			return null;
		return ffi.ForeignFunction(buf, ret, args);
	};
	r.set = function set(buf, offset, val) {
		return ref.set(buf, offset, ffi.Callback(ret, args, void(0), val));
	};
	return r;
};

var defaults = {
	forEach: function forEach(callback, thisArg) {
		if({}.toString.call(callback) != '[object Function]')
			throw new TypeError(callback + ' is not a function');

		for(var T = thisArg || T, iter = this.iterator(); iter; iter = iter.get_next())
			callback.call(T, iter.get_data(), iter, this);
	}
};

function bindings(s) {
	function method(name, ret, args, static, more) {
		var f = (more == 'variadic' ? ffi.VariadicForeignFunction :
			ffi.ForeignFunction)(lib.get(name), ret, args);
		if(static)
			return f;
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

	function define(base, n, m) {
		var static = n[0] == '$' && ((n = n.slice(1)), true);
		static = static || base[0] == '$' && ((base = base.slice(1)), true);
		if(Array.isArray(m))
			m = method(m[0], m[1], m[2], static, m[3]);
		static ? exports[base][n] = m : types[base].prototype[n] = m;
	}

	function makeGeneric(G, n) {
		var cache = [], cacheTo = [];
		types[n] = function() {
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
			generic.$name = n+'<'+args.map(function(T) {return Tname(T);}).join(', ')+'>';

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
			makeGeneric(s[i], i);
		else if(i[0] == '$')
			exports[i.slice(1)] = {};
		else
			exports[i] = types[i] = Struct(), types[i].$name = i;
	}
	for(var i in s) {
		if(s[i].length) {
			// TODO insert constructor
			delete s[i];
			continue;
		}
		s[i] = s[i]();
		if(Array.isArray(s[i])) {
			for(var j in s[i][0])
				types[i].defineProperty(j, s[i][0][j]);
			s[i] = s[i][1];
		}
	}
	for(var i in s) {
		if('$constructor' in s[i]) {
			var ctor = s[i].$constructor;
			exports[i] = method(ctor[0], ctor[1], ctor[2], true, ctor[3]), exports[i].$type = types[i];
			delete s[i].$constructor;
		}
		for(var j in s[i])
			define(i, j, s[i][j]);
	}
}
var _ = types;
bindings({\n"+bind+"\n});
"
		);}

		if (enum_fmt != "") {
			string enums_exec, enums_out = "";
			try {
				FileUtils.close (FileUtils.open_tmp ("vbeXXXXXX", out enums_exec));
			} catch (FileError e) {
				error (e.message);
			}
			string[] gcc_args = {"gcc", "-x", "c", "-o", enums_exec, "-"};
			foreach (var i in include_dirs)
				gcc_args += "-I"+i;
			try {
				Pid gcc_pid;
				int gcc_stdinfd;
				Process.spawn_async_with_pipes (null, gcc_args, null,
					SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
					null, out gcc_pid, out gcc_stdinfd);
				var gcc_stdin = FileStream.fdopen (gcc_stdinfd, "w");
				if (gcc_stdin == null)
					throw new SpawnError.IO ("Cannot open gcc's stdin");
				foreach (string i in includefiles)
					gcc_stdin.printf ("#include <%s>\n", i);
				gcc_stdin.printf ("int main(){printf(\"%s\"%s);return 0;}\n", enum_fmt, enum_vals);
				gcc_stdin = null;
				int status;
				Posix.waitpid (gcc_pid, out status, 0);
				Process.close_pid (gcc_pid);
				if (status != 0)
					throw new SpawnError.FAILED ("gcc exited with status %d", status);

				Process.spawn_sync (null, {enums_exec}, null, 0, null, out enums_out, null, out status);
				if (status != 0)
					throw new SpawnError.FAILED ("enums helper exited with status %d", status);
			} catch (SpawnError e) {
				FileUtils.unlink (enums_exec);
				error (e.message);
			}
			FileUtils.unlink (enums_exec);
			stream.puts (enums_out);
		}
	}
}
