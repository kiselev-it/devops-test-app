
BRANCH ?= master

build-app:
	docker build app --tag quay.csssr.cloud/csssr/test-app:$(BRANCH)
	docker push quay.csssr.cloud/csssr/test-app:$(BRANCH)

HELM ?= helm3

deploy:
	$(HELM) upgrade --install my-app-$(BRANCH) chart --set image.tag=$(BRANCH) --set ingress.host=$(BRANCH).my-app.com
