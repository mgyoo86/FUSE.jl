JULIA_PKG_DEVDIR ?= $(HOME)/.julia/dev
CURRENTDIR = $(shell pwd)

all:
	@echo 'FUSE makefile help'
	@echo ''
	@echo ' - make install  : install FUSE and all of its dependencies'
	@echo ' - make update   : update FUSE and all of its dependencies'
	@echo ''

install: install_FUSE install_IJulia
	julia -e '\
using Pkg;\
Pkg.activate();\
Pkg.develop(["FUSE", "IMAS", "CoordinateConventions", "AD_GS", "Equilibrium"]);\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

install_IJulia:
	julia -e '\
using Pkg;\
Pkg.add("IJulia");\
'

install_FUSE: install_IMAS install_CoordinateConventions install_FusionMaterials install_AD_GS install_Equilibrium
	if [ ! -d "$(JULIA_PKG_DEVDIR)/FUSE" ]; then ln -s $(CURRENTDIR) $(JULIA_PKG_DEVDIR)/FUSE; fi
	julia -e '\
using Pkg;\
Pkg.activate("$(JULIA_PKG_DEVDIR)/FUSE");\
Pkg.develop(["IMAS", "CoordinateConventions", "FusionMaterials", "AD_GS", "Equilibrium"]);\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

install_IMAS: install_CoordinateConventions
	if [ ! -d "$(JULIA_PKG_DEVDIR)/IMAS" ]; then\
		julia -e 'using Pkg; Pkg.develop(url="git@github.com:ProjectTorreyPines/IMAS.jl.git");';\
	fi
	julia -e '\
using Pkg;\
Pkg.activate("$(JULIA_PKG_DEVDIR)/IMAS");\
Pkg.develop(["CoordinateConventions"]);\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

install_CoordinateConventions:
	if [ ! -d "$(JULIA_PKG_DEVDIR)/CoordinateConventions" ]; then\
		julia -e 'using Pkg; Pkg.develop(url="git@github.com:ProjectTorreyPines/CoordinateConventions.jl.git");';\
	fi
	julia -e '\
using Pkg;\
Pkg.activate("$(JULIA_PKG_DEVDIR)/CoordinateConventions");\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

install_FusionMaterials:
	if [ ! -d "$(JULIA_PKG_DEVDIR)/FusionMaterials" ]; then\
		julia -e 'using Pkg; Pkg.develop(url="git@github.com:ProjectTorreyPines/FusionMaterials.jl.git");';\
	fi
	julia -e '\
using Pkg;\
Pkg.activate("$(JULIA_PKG_DEVDIR)/FusionMaterials");\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

install_AD_GS: install_Equilibrium
	if [ ! -d "$(JULIA_PKG_DEVDIR)/AD_GS" ]; then\
		julia -e 'using Pkg; Pkg.develop(url="git@github.com:ProjectTorreyPines/AD_GS.jl.git");';\
	fi
	julia -e '\
using Pkg;\
Pkg.activate("$(JULIA_PKG_DEVDIR)/AD_GS");\
Pkg.develop(["Equilibrium", "CoordinateConventions"]);\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

install_Equilibrium: install_CoordinateConventions
	if [ ! -d "$(JULIA_PKG_DEVDIR)/Equilibrium" ]; then\
		julia -e 'using Pkg; Pkg.develop(url="git@github.com:ProjectTorreyPines/Equilibrium.jl.git");';\
	fi
	julia -e '\
using Pkg;\
Pkg.activate("$(JULIA_PKG_DEVDIR)/Equilibrium");\
Pkg.develop(["CoordinateConventions"]);\
Pkg.resolve();\
try Pkg.upgrade_manifest() catch end;\
'

update: update_FUSE update_IMAS update_AD_GS update_Equilibrium update_CoordinateConventions update_FusionMaterials
	make install

update_FUSE:
	cd $(JULIA_PKG_DEVDIR)/FUSE; git fetch; git pull

update_IMAS:
	cd $(JULIA_PKG_DEVDIR)/IMAS; git fetch; git pull

update_AD_GS:
	cd $(JULIA_PKG_DEVDIR)/AD_GS; git fetch; git pull

update_Equilibrium:
	cd $(JULIA_PKG_DEVDIR)/Equilibrium; git fetch; git pull

update_CoordinateConventions:
	cd $(JULIA_PKG_DEVDIR)/CoordinateConventions; git fetch; git pull

update_FusionMaterials:
	cd $(JULIA_PKG_DEVDIR)/FusionMaterials; git fetch; git pull

.PHONY:
