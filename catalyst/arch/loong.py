
from catalyst import builder

class generic_loong(builder.generic):
	"abstract base class for all loong builders"
	def __init__(self,myspec):
		builder.generic.__init__(self,myspec)
		self.settings["COMMON_FLAGS"]="-O2 -pipe"
		self.settings["CHOST"]="loongarch64-unknown-linux-gnu"

class arch_loong(generic_loong):
	"builder class for generic loong"
	def __init__(self,myspec):
		generic_loong.__init__(self,myspec)

class arch_la64_baseline_multilib(generic_loong):
	"builder class for la64_baseline_multilib"
	def __init__(self,myspec):
		generic_loong.__init__(self,myspec)

class arch_la64_baseline_lp64(generic_loong):
	"builder class for la64_baseline_lp64"
	def __init__(self,myspec):
		generic_loong.__init__(self,myspec)
		self.settings["COMMON_FLAGS"]="-O2 -pipe -mabi=lp64"

def register():
	"Inform main catalyst program of the contents of this plugin."
	return ({
		"loong"				: arch_loong,
		"loongarch64"			: arch_loong,
		"la64_baseline_multilib"	: arch_la64_baseline_multilib,
		"la64_baseline_lp64"    	: arch_la64_baseline_lp64,
		}, ("la64_multilib"))
