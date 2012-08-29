# RAsm ctypes example #
from ctypes import *
from ctypes.util import find_library

# helper functions

lib = CDLL (find_library ("r_asm"))
free = getattr (lib, "free")

def register (self, name, cname, args, ret):
	g = globals ()
	g['self'] = self
	if (ret!='' and ret[0]>='A' and ret[0]<='Z'):
		last = ".contents"
		ret = "POINTER("+ret+")"
		ret2 = ""
	else:
		last = ""
		ret2 = ret
	setattr (self,cname, getattr (lib, cname))
	exec ("self.%s.argtypes = [%s]"%(cname, args))
	if ret != "":
		exec ("self.%s.restype = %s"%(cname, ret), g)
	exec ("self.%s = lambda x: %s(self.%s(self._o, x))%s"%
		(name, ret2, cname, last),g)

# define classes

class RAsmCode(Structure):
	_fields_ = [
		("len", c_int),
		("buf", c_char_p),
		("buf_hex", c_char_p),
		("buf_asm", c_char_p)
	]

class RAsm(Structure):
	_fields_ = [
		("bits", c_int),
		("big_endian", c_int),
		("syntax", c_int),
		("pc", c_ulonglong)
	]
	def __init__(self):
		r_asm_new = getattr (lib, "r_asm_new");
		r_asm_new.restype = c_void_p
		self._o = r_asm_new ()
		register (self, 'use', 'r_asm_use', 'c_void_p, c_char_p', 'c_bool')
		register (self, '__del__', 'r_asm_free', 'c_void_p', '')
		register (self, 'set_pc', 'r_asm_set_pc', 'c_void_p, c_ulonglong', 'c_bool')
		register (self, 'set_bits', 'r_asm_set_bits', 'c_void_p, c_int', 'c_bool')
		register (self, 'massemble', 'r_asm_massemble', 'c_void_p, c_char_p', 'RAsmCode')
		register (self, 'mdisassemble_hexstr', 'r_asm_mdisassemble_hexstr',
			'c_void_p, c_char_p', 'RAsmCode')


# Example

a = RAsm()
ok0 = a.use ("x86")
ok1 = a.set_bits (32)
ok2 = a.mdisassemble_hexstr ("909090")
ok4 = a.set_pc (0x8048000)
print (ok0, ok1, a, ok4)
print ("Disasm len: ",ok2.len)
print ("Disasm buf: ",ok2.buf_hex)
print ("Disasm asm: ",ok2.buf_asm)
print (ok2.buf_asm)

# print (a.SYNTAX.INTEL)

ok3 = a.massemble ("mov eax, 33")
print ("Assemble hex:", ok3.buf_hex)
a = None
