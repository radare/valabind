import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;
import com.sun.jna.Structure;

public class RAsmCode extends Structure {
	public int len;
	public String buf;
	public String buf_hex;
	public String buf_asm;
}
