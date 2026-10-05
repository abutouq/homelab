# Packer image builds. Run from this directory:
#   make all               build base, then vault, teleport and grafana (skips images that already exist)
#   make teleport          build one role image (builds base first if missing)
#   make rebuild-all       delete and rebuild every image, base first
#   make rebuild-teleport  delete that role's template on the node, then build it again
# The token secret comes from the gitignored secrets.auto.pkrvars.hcl.
# To add an image: write <name>.pkr.hcl, then add it to ROLES and give it an ID_<name> below.

PVE_HOST := root@192.168.0.201
BASE_ID  := 9300

ROLES := vault teleport grafana
ID_vault    := 9301
ID_teleport := 9302
ID_grafana  := 9303

.PHONY: rebuild-all all init validate base rebuild-base $(ROLES) $(addprefix rebuild-,$(ROLES))

all: base $(ROLES)

rebuild-all: rebuild-base $(addprefix rebuild-,$(ROLES))

init:
	packer init .

validate: init
	packer fmt -check .
	packer validate .

# Packer fails if the VM ID is taken, so building an existing image is a no-op.
base: validate
	@if ssh $(PVE_HOST) 'qm status $(BASE_ID)' >/dev/null 2>&1; then echo "template $(BASE_ID) exists, skipping (make rebuild-base to replace)"; \
	else packer build -only='proxmox-iso.ubuntu' .; fi

# Deleting the base does not affect images already built from it (they are full clones).
rebuild-base:
	ssh $(PVE_HOST) 'qm destroy $(BASE_ID) --purge'
	$(MAKE) base

define ROLE_RULES
$(1): validate
	@if ssh $(PVE_HOST) 'qm status $$(ID_$(1))' >/dev/null 2>&1; then echo "template $$(ID_$(1)) exists, skipping (make rebuild-$(1) to replace)"; \
	else $$(MAKE) --no-print-directory base && packer build -only='proxmox-clone.$(1)' .; fi

rebuild-$(1):
	ssh $(PVE_HOST) 'qm destroy $$(ID_$(1)) --purge'
	$$(MAKE) $(1)
endef

$(foreach role,$(ROLES),$(eval $(call ROLE_RULES,$(role))))
