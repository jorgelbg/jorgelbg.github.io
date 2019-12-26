YEAR := $(shell date +%Y)
POSTS_PATH := 'content/posts/${YEAR}'

.PHONY: run
run:
	hugo serve -EDF

.PHONY: new
new: # Create a new article
	@echo "Bootstrapping new article"
	$(if $(word 2,$(MAKECMDGOALS)), hugo new ${POSTS_PATH}/$(word 2,$(MAKECMDGOALS)), "Specify the filename")

.PHONY: empty
%:
	@echo $(if $(filter $(word 1,$(MAKECMDGOALS)), new),"", "Unknown target")