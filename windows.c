/* Copyleft 2015 -- pancake */

#include <windows.h>

void w32_exit(int x) {
	ExitProcess (x);
}

int w32_waitpid (int processId) {
	HANDLE      nProc;
	DWORD       dwExitCode;

	nProc = OpenProcess (PROCESS_ALL_ACCESS, TRUE, processId);
	if (nProc != NULL) {
		GetExitCodeProcess (nProc, &dwExitCode);
		if (dwExitCode == STILL_ACTIVE )
			return dwExitCode; //RC_PROCESS_EXIST;
	}
	return -1;
}
