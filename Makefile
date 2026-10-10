# Shortcuts for the scripts in scripts/.
#
#   make build     dist/site/ for production (STAGE=rc for the release candidate)
#   make serve     the dev server on http://localhost:1415/ (rebuilds on change)
#   make rc        tag and push a release candidate (deploys rc.nu01.com)
#   make ga        tag and push GA (deploys nu01.com; needs a live, tested RC)
#   make clean     remove dist/

.PHONY: build serve rc ga clean

build:
	@bash scripts/build.sh
serve:
	@bash scripts/serve.sh
rc:
	@bash scripts/release-rc.sh
ga:
	@bash scripts/release-ga.sh
clean:
	rm -rf dist
