YEAR := $(shell date +%Y)
POSTS_PATH := 'posts/${YEAR}'
IMAGES_PATH := 'static/images'

.PHONY: run
run:
	hugo serve -EDF

.PHONY: new
new: # Create a new article
	@echo "Bootstrapping new article"
	$(if $(word 2,$(MAKECMDGOALS)), hugo new ${POSTS_PATH}/$(word 2,$(MAKECMDGOALS)).md, "Specify the article slug")
	@echo "Creating image directory"
	$(if $(word 2,$(MAKECMDGOALS)), mkdir -p ${IMAGES_PATH}/$(word 2,$(MAKECMDGOALS)), "Specify the article slug")

.PHONY: empty
%:
	@echo $(if $(filter $(word 1,$(MAKECMDGOALS)), new),"", "Unknown target")