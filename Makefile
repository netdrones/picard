GIT_HEAD_REF := $(shell git rev-parse HEAD)

BASE_IMAGE := pytorch/pytorch:1.8.1-cuda11.1-cudnn8-devel

DEV_IMAGE_NAME := text-to-sql-dev
TRAIN_IMAGE_NAME := text-to-sql-train
EVAL_IMAGE_NAME := text-to-sql-eval

BUILDKIT_IMAGE := tscholak/text-to-sql-buildkit:buildx-stable-1
BUILDKIT_BUILDER ?= buildx-local

.PHONY: init-buildkit
init-buildkit:
	docker buildx create \
		--name buildx-local \
		--driver docker-container \
		--driver-opt image=$(BUILDKIT_IMAGE),network=host \
		--use

.PHONY: del-buildkit
del-buildkit:
	docker buildx rm buildx-local

.PHONY: build-thrift-code
build-thrift-code:
	thrift1 --gen mstch_cpp2 picard.thrift
	thrift1 --gen mstch_py3 picard.thrift
	cd gen-py3 && python setup.py build_ext --inplace

.PHONY: build-picard-deps
build-picard-deps:
	cabal update
	thrift-compiler --hs --use-hash-map --use-hash-set --gen-prefix gen-hs -o . picard.thrift
	patch -p 1 -N -d third_party/hsthrift < ./fb-util-cabal.patch || true
	cd third_party/hsthrift \
		&& make THRIFT_COMPILE=thrift-compiler thrift-cpp thrift-hs
	cabal build --only-dependencies lib:picard

.PHONY: build-picard
build-picard:
	cabal install --overwrite-policy=always --install-method=copy exe:picard

.PHONY: build-dev-image
build-dev-image:
	ssh-add
	docker buildx build \
		--builder $(BUILDKIT_BUILDER) \
		--ssh default=$(SSH_AUTH_SOCK) \
		-f Dockerfile \
		--tag tscholak/$(DEV_IMAGE_NAME):$(GIT_HEAD_REF) \
		--tag tscholak/$(DEV_IMAGE_NAME):cache \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--target dev \
		--cache-from type=registry,ref=tscholak/$(DEV_IMAGE_NAME):cache \
		--cache-to type=inline \
		--push \
		git@github.com:ElementAI/picard#$(GIT_HEAD_REF)

.PHONY: pull-dev-image
pull-dev-image:
	docker pull tscholak/$(DEV_IMAGE_NAME):$(GIT_HEAD_REF)

.PHONY: build-train-image
build-train-image:
	ssh-add
	docker buildx build \
		--builder $(BUILDKIT_BUILDER) \
		--ssh default=$(SSH_AUTH_SOCK) \
		-f Dockerfile \
		--tag tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF) \
		--tag tscholak/$(TRAIN_IMAGE_NAME):cache \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--target train \
		--cache-from type=registry,ref=tscholak/$(TRAIN_IMAGE_NAME):cache \
		--cache-to type=inline \
		--push \
		git@github.com:ElementAI/picard#$(GIT_HEAD_REF)

.PHONY: pull-train-image
pull-train-image:
	docker pull tscholak/$(TRAIN_IMAGE_NAME):$(GIT_HEAD_REF)

.PHONY: build-eval-image
build-eval-image:
	ssh-add
	docker buildx build \
		--builder $(BUILDKIT_BUILDER) \
		--ssh default=$(SSH_AUTH_SOCK) \
		-f Dockerfile \
		--tag tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF) \
		--tag tscholak/$(EVAL_IMAGE_NAME):cache \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		--target eval \
		--cache-from type=registry,ref=tscholak/$(EVAL_IMAGE_NAME):cache \
		--cache-to type=inline \
		--push \
		git@github.com:ElementAI/picard#$(GIT_HEAD_REF)

.PHONY: pull-eval-image
	docker pull tscholak/$(EVAL_IMAGE_NAME):$(GIT_HEAD_REF)

