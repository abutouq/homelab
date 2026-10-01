# Packer image builds. Run from this directory:
#   make all           build base, then vault (skips images that already exist)
#   make rebuild-vault delete template 9301 on the node, then build it again
# The token secret comes from the gitignored secrets.auto.pkrvars.hcl.

PVE_HOST := root@192.168.0.201
BASE_ID  := 9300
VAULT_ID := 9301

.PHONY: all init validate base vault rebuild-base rebuild-vault

all: base vault

init:
	packer init .

validate: init
	packer fmt -check .
	packer validate .

# Packer fails if the VM ID is taken, so building an existing image is a no-op.
base: validate
	@if ssh $(PVE_HOST) 'qm status $(BASE_ID)' >/dev/null 2>&1; then echo "template $(BASE_ID) exists, skipping (make rebuild-base to replace)"; \
	else packer build -only='proxmox-iso.ubuntu' .; fi

vault: validate
	@if ssh $(PVE_HOST) 'qm status $(VAULT_ID)' >/dev/null 2>&1; then echo "template $(VAULT_ID) exists, skipping (make rebuild-vault to replace)"; \
	else $(MAKE) --no-print-directory base && packer build -only='proxmox-clone.vault' .; fi

# Deleting the base does not affect images already built from it (they are full clones).
rebuild-base:
	ssh $(PVE_HOST) 'qm destroy $(BASE_ID) --purge'
	$(MAKE) base

rebuild-vault:
	ssh $(PVE_HOST) 'qm destroy $(VAULT_ID) --purge'
	$(MAKE) vault
