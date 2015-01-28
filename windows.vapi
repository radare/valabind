[CCode (cheader_filename="windows.h", cname="w32")]
namespace Windows {
	public static int waitpid(int pid);
	public static void exit(int rc);
}
