YEAR := $(shell date +%Y)

.PHONY: run
run:
	hugo serve -E -D

.PHONY: new
new: # Create a new article
	@echo $(if $(word 2,$(MAKECMDGOALS)), hugo new posts/${YEAR}/$(word 2,$(MAKECMDGOALS)), "Specify the filename")

.PHONY: empty
%:
	@echo $(if $(filter $(word 1,$(MAKECMDGOALS)), new),"", "Unknown target")