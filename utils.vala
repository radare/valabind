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
#if VALA_0_25 || VALA_0_26
	/* If valac >= 0.25 use this workaround to resolve the array length */
	if (array.fixed_length && array.length is Vala.IntegerLiteral) {
		Vala.IntegerLiteral lit = (Vala.IntegerLiteral) array.length;
		return int.parse (lit.value);
	}
	return -1;
#else
	return array.length;
#endif
}

// TODO: make it reusable for other backends
public string get_enums_for (string str, GLib.List<string> includefiles) {
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
		gcc_stdin.printf ("int main(){%s;return 0;}\n", str);
		gcc_stdin = null;
		int status;
#if W32
		status = Windows.waitpid (gcc_pid);
#else
		Posix.waitpid (gcc_pid, out status, 0);
#endif

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
	return enums_out;
}
