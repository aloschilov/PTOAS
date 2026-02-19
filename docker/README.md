The Docker build is **split so LLVM is never rebuilt** when you change PTOAS:

1. **LLVM image** (build once, or when you change LLVM version): uses an **empty context** so no clone/build depends on the repo. Rebuilding this image is the only way to change LLVM.
2. **PTOAS image**: `FROM ptoas-llvm:19` then `COPY . PTOAS` and build PTOAS. Any repo change only affects from the COPY step onward.

Build:

```bash
# 1) Build LLVM image once (empty context = no repo dependency; matches Triton v3.1.0 / LLVM 19.0.0)
docker build -f docker/Dockerfile.llvm -t ptoas-llvm:19 docker/empty

# 2) From repo root, build PTOAS image (uses local source)
docker build -f docker/Dockerfile . -t ptoas:py3.11
# py3.11 to match CANN images: https://quay.io/repository/ascend/cann?tab=tags

# Optional: different Python/LLVM when building the LLVM image
docker build -f docker/Dockerfile.llvm -t ptoas-llvm:19 docker/empty --build-arg PY_VER=cp312-cp312
docker build -f docker/Dockerfile.llvm -t ptoas-llvm:19 docker/empty --build-arg LLVM_REF=<commit-or-tag>
```

To test compiler:

```bash
sudo docker run --rm -it \
    -v $HOME:/mounted_home -w /mounted_home \
    ptoas:py3.11 /bin/bash

cd /sources/test/Abs
python ./abs.py > ./abs.pto
ptoas --enable-insert-sync ./abs.pto -o ./abs.cpp

# temporary fix for macro guards, better let `ptoas` insert it
(echo '#if __CCE_AICORE__ == 220 && defined(__DAV_C220_VEC__)'; cat abs.cpp; echo '#endif') > abs.cpp.tmp && mv abs.cpp.tmp abs.cpp

bisheng \
    -I${PTO_LIB_PATH}/include/pto \
    -fPIC -shared -O2 -std=c++17 \
    --npu-arch=dav-2201 -DMEMORY_BASE \
    ./abs.cpp \
    -o ./abs_kernel.so
```

To run on device:

```bash
sudo docker run --rm -it --ipc=host --privileged \
    --device=/dev/davinci0 --device=/dev/davinci1 \
    --device=/dev/davinci2 --device=/dev/davinci3 \
    --device=/dev/davinci4 --device=/dev/davinci5 \
    --device=/dev/davinci6 --device=/dev/davinci7 \
    --device=/dev/davinci_manager \
    --device=/dev/devmm_svm \
    --device=/dev/hisi_hdc  \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
    -v /etc/ascend_install.info:/etc/ascend_install.info:ro \
    -v $HOME:/mounted_home -w /mounted_home \
    ptoas:py3.11 /bin/bash
```