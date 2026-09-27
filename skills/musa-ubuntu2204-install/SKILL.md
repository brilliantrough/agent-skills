---
name: musa-ubuntu2204-install
description: Use when installing, upgrading, or troubleshooting Moore Threads MUSA, torch_musa, muDNN, MCCL, mtgpu, or MTT S5000 on Ubuntu 22.04 x86_64; covers portable user-space installs, Python compatibility, dynamic libraries, and validation.
---

# MUSA on Ubuntu 22.04 x86_64

Scope: `portable`. Use this for an arbitrary compatible Ubuntu 22.04 host;
current-server facts belong in `musa-local-server`.

Use this skill for a new or existing Ubuntu 22.04 x86_64 host. Do not assume paths, package versions, GPU models, or driver state from another machine.

## Operating principles

1. Separate the kernel driver from the user-space SDK.
2. Treat Toolkit, user-space `libmusa`, muDNN, MCCL, torch, and torch_musa as one compatibility set.
3. Prefer a versioned user-space prefix so changing SDKs does not rewrite the host.
4. Never upgrade or reload the kernel driver while GPU jobs are running.
5. Validate dynamic linking before running a model.
6. A successful `musaInfo` query does not prove that a torch_musa wheel is compatible.

## Architecture

The kernel side normally contains:

- `mtgpu` kernel module.
- GPU firmware.
- Device nodes and management integration.
- Exactly one active kernel driver version.

The selectable user-space side contains:

- `libmusa.so.1`, analogous to the CUDA driver API library.
- MUSA Toolkit and `libmusart.so`.
- muBLAS, muFFT, muSPARSE, muSOLVER, and related math libraries.
- muDNN.
- MCCL.
- Compiler and tools such as `mcc`, `musaInfo`, and `musa_version_query`.
- Python, torch, and torch_musa.

Multiple user-space versions can coexist. The kernel module does not coexist in the same way.

## Inspect before changing anything

Run read-only checks first:

```bash
lsb_release -a
uname -a
lscpu
lspci -nn
mthreads-gmi
lsmod | awk '$1 == "mtgpu" {print}'
dkms status
```

Record:

- Ubuntu point release and kernel.
- CPU architecture.
- GPU model and count.
- Kernel driver package/version.
- Existing `/usr/local/musa*`, `/opt/MUSA*`, PATH, and LD_LIBRARY_PATH.
- Active GPU processes and containers.

Do not infer a complete Toolkit install from `mthreads-gmi` alone.

## Choose a compatibility set

Consult the current official release notes and torch_musa release page. Record a matrix with these columns before installing:

```text
GPU model
compute capability
kernel driver
user-space libmusa
Toolkit
muDNN
MCCL target architecture
Python ABI
torch
torch_musa
```

Rules:

- `torch` and `torch_musa` versions must match exactly.
- A wheel tagged `musa5.2.0` expects the MUSA 5.2 user-space stack.
- Use `mccl-s5000` for S5000, not the S4000 build.
- Python wheel tags such as `cp310` and `cp312` must match the interpreter.
- Do not let a normal PyPI torch wheel replace the MUSA torch wheel.

Official references:

- `https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/install_guide`
- `https://developer.mthreads.com/sdk/download/musa`
- `https://github.com/MooreThreads/torch_musa`
- `https://dl.mthreads.com/repo/api/pypi/pypi/simple/torch-musa/`

## Versioned user-space layout

Use a writable root chosen for that host:

```bash
export MUSA_ROOT="${MUSA_ROOT:-$HOME/opt/musa}"
export MUSA_VERSION=5.2.0
export MUSA_HOME="$MUSA_ROOT/$MUSA_VERSION"
export MUSA_DRIVER_LIB_DIR="$MUSA_ROOT/runtime-deps/$MUSA_VERSION/lib"
```

A useful layout is:

```text
$MUSA_ROOT/
├── 4.3.5/
├── 5.1.0/
├── 5.2.0/
├── runtime-deps/
│   ├── 4.3.5/lib/
│   ├── 5.1.0/lib/
│   └── 5.2.0/lib/
└── downloads/
```

Do not assume the vendor installer supports this layout. Inspect `install.sh -h` first. If it accepts `--prefix`, use it. Otherwise extract DEBs or archives into a staging root and move only the user-space tree.

## Download and integrity

Prefer the official offline SDK bundle or official Ubuntu repository.

For repository-based installation:

1. Download the Moore Threads repository configuration DEB without installing it.
2. Extract its source-list entry and keyring with `dpkg-deb -x`.
3. Use an isolated APT state/cache directory under the chosen MUSA root.
4. Verify `Release.gpg` with the extracted keyring.
5. Verify package hashes through APT or against the signed `Packages` index.

For MUSA 5.2, the relevant package families include:

```text
musa-toolkit-5-2
musa-musart-5-2
libmudnn3-musa-5-2
mccl-s5000
libmthreads-compute
```

Do not request `mthreads-driver` or `mthreads-dkms` for a user-space-only install.

Download dependency closure with APT in download-only mode, then extract each DEB:

```bash
dpkg-deb -x package.deb "$STAGING_ROOT"
```

Packages commonly place the Toolkit under:

```text
$STAGING_ROOT/usr/local/musa-X.Y
```

Move that directory to the selected `$MUSA_HOME`. Keep `libmusa.so.1` from `libmthreads-compute` in the matching versioned runtime directory.

## Manual environment configuration

Environment variables are the portable interface. Scripts and modules are optional wrappers around these settings:

```bash
export MUSA_HOME="$MUSA_ROOT/$MUSA_VERSION"
export MUSA_INSTALL_PATH="$MUSA_HOME"
export PATH="$MUSA_HOME/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="$MUSA_DRIVER_LIB_DIR:$MUSA_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

Ordering matters:

1. Matching user-space `libmusa.so.1` directory.
2. Matching Toolkit/muDNN/MCCL library directory.
3. Existing inherited library paths.

Set visible GPUs separately:

```bash
export MUSA_VISIBLE_DEVICES="${MUSA_VISIBLE_DEVICES:?set the allocated device list}"
```

`CUDA_VISIBLE_DEVICES` is not a portable substitute for native MUSA code.

For shared HPC systems, Environment Modules can set the same variables. For project-local workflows, an explicit `envs.sh` can set them. Do not hide critical MUSA variables only inside Conda activation hooks.

## MPI, MKL, and Python dependencies

Some MUSA torch wheels directly require:

```text
libmpi.so.40
libmkl_intel_lp64.so.2
libmkl_gnu_thread.so.2
libmkl_core.so.2
```

Check the wheel rather than assuming:

```bash
ldd /path/to/torch/lib/libtorch_global_deps.so
ldd /path/to/torch_musa/lib/libmusa_python.so.*
```

OpenMPI and MKL may be installed in the Conda environment, a versioned local runtime directory, or the system. Keep their library directories explicit in `LD_LIBRARY_PATH` when they are not registered with the system loader.

If torch reports that an extension compiled against NumPy 1.x cannot run with NumPy 2.x, use a compatible `numpy<2` version or rebuild the extension. Python 3.12 commonly uses `numpy==1.26.4` for this compatibility case.

## Install Python packages

Create a clean Python environment with a supported ABI. Install the matching MUSA torch and torch_musa wheels from the official Moore Threads index. Keep application dependencies separate from the accelerator stack.

After installation, record:

```bash
python -V
python -m pip show torch torch_musa
python -m pip check
```

Do not install unmodified CUDA dependency files containing `nvidia-*`, CUDA Triton, bitsandbytes, BitBLAS, NCCL, or CUDA-only custom extensions into a MUSA environment.

## Validation ladder

Validate from lowest to highest risk.

Toolkit and driver API:

```bash
which mcc musaInfo musa_version_query mccl_version
musa_version_query
musaInfo
mccl_version
mcc --version
```

Dynamic libraries:

```bash
ldd /path/to/libmusa_python.so | awk '/not found/ {print}'
ldd /path/to/libtorch_global_deps.so | awk '/not found/ {print}'
```

Single-device torch:

```bash
python - <<'PY'
import torch
import torch_musa

print(torch.__version__)
print(torch_musa.__version__)
print(torch.musa.is_available())
print(torch.musa.device_count())
x = torch.randn(64, 64, device="musa", dtype=torch.bfloat16)
y = x @ x
torch.musa.synchronize()
print(y.shape, y.dtype)
PY
```

Then validate, in order:

1. One-process MCCL.
2. Two-process `torchrun` MCCL all-reduce.
3. Short application workload.
4. All-device communication.
5. Long-running training stability.

## Failure patterns

`libmpi.so.40` missing:

- Install/extract an OpenMPI 4.1 runtime or the version required by the wheel.
- Check secondary dependencies of `libmpi.so.40` with `ldd`.

MKL libraries missing:

- Install/extract the MKL runtime libraries required by `libtorch_global_deps.so`.
- Do not solve only the first missing library and stop checking.
- If torch import then fails on `iJIT_NotifyEvent`, the selected MKL is ABI-incompatible with the wheel. Pin a compatible older MKL row and record it; do not assume the newest MKL with matching SONAMEs is compatible.

`undefined symbol` from muBLAS, muDNN, or torch_musa:

- A mismatched `libmusa`, Toolkit, or wheel is being loaded.
- Inspect `LD_LIBRARY_PATH` order and `ldd` output.
- Do not copy a random `.so` into the Python package.

`musaInfo` works but torch import fails:

- Toolkit queries prove only the C/C++ user stack.
- Verify torch, torch_musa, Python ABI, MPI, MKL, and NumPy separately.

No devices or kernel errors:

- Stop user-space debugging and inspect kernel driver, firmware, IOMMU/VT-d requirements, device nodes, and hardware support.
- Schedule driver changes only after draining GPU jobs.

## Completion criteria

An environment is complete only when:

- Versions and installation source are documented.
- `PATH` and `LD_LIBRARY_PATH` are explicit and reproducible.
- `ldd` reports no missing libraries.
- Single-device compute succeeds.
- Required MCCL topology succeeds.
- The real application completes a short smoke workload.
- Rollback consists of selecting another prefix or deleting the local directory, not repairing the host package database.
