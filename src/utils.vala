/* Copyright 2009-2015 -- pancake, ritesh */

#if W32
using Windows;
#endif

public void notice (string msg) {
	stderr.printf ("\x1b[34;1mNOTICE\x1b[0m %s\n", msg);
}

public void warning (string msg) {
	stderr.printf ("\x1b[33;1mWARNING\x1b[0m %s\n", msg);
}

public void error (string msg) {
	stderr.printf ("\x1b[31;1mERROR\x1b[0m %s\n", msg);
#if W32
	Windows.exit (1);
#else
	Posix.exit (1);
#endif
}

// TODO: check out if this is really required ?
public int array_length (Vala.ArrayType array) {
	/* If valac >= 0.25 use this boilerplate to resolve the array length */
	if (array.fixed_length && array.length is Vala.IntegerLiteral) {
		Vala.IntegerLiteral lit = (Vala.IntegerLiteral) array.length;
		return int.parse (lit.value);
	}
	return -1;
}

// TODO: make it reusable for other backends
public string get_enums_for (string str, GLib.List<string> includefiles) {
	string enums_exec, enums_out = "";
	try {
		FileUtils.close (FileUtils.open_tmp ("vbeXXXXXX", out enums_exec));
	} catch (FileError e) {
		error (e.message);
	}
	string cc = Environment.get_variable ("CC");
	if (cc == null || cc == "")
		cc = "cc";
	string[] cc_args = {cc, "-x", "c", "-o", enums_exec, "-"};
	foreach (var i in include_dirs)
		cc_args += "-I"+i;
	try {
		Pid cc_pid;
		int cc_stdinfd;
		Process.spawn_async_with_pipes (null, cc_args, null,
				SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
				null, out cc_pid, out cc_stdinfd);
		var cc_stdin = FileStream.fdopen (cc_stdinfd, "w");
		if (cc_stdin == null)
			throw new SpawnError.IO ("Cannot open %s's stdin".printf (cc));
		foreach (string i in includefiles)
			cc_stdin.printf ("#include <%s>\n", i);
		cc_stdin.printf ("int main(){%s;return 0;}\n", str);
		cc_stdin = null;
		int status;
#if W32
		status = Windows.waitpid (cc_pid);
#else
		Posix.waitpid (cc_pid, out status, 0);
#endif

		Process.close_pid (cc_pid);
		if (status != 0)
			throw new SpawnError.FAILED ("%s exited with status %d", cc, status);
		Process.spawn_sync (null, {enums_exec}, null, 0, null, out enums_out, null, out status);
		if (status != 0)
			throw new SpawnError.FAILED ("enums helper exited with status %d", status);
	} catch (SpawnError e) {
		FileUtils.unlink (enums_exec);
		error (e.message);
	}
	FileUtils.unlink (enums_exec);
	return enums_out;
}
