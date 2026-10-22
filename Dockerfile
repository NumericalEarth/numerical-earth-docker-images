# syntax=docker/dockerfile:1
ARG JULIA_VERSION=1.12.5
FROM julia:${JULIA_VERSION}

# Install some dependencies
RUN /bin/sh -c 'export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates earlyoom git gpg jq \
    && apt-get --purge autoremove -y \
    && apt-get autoclean \
    && rm -rf /var/lib/apt/lists/*'

# Docker is awful and doesn't allow conditionally setting environment variables in a decent
# way, so we have to keep an external script and source it every time we need it.
COPY julia_cpu_target.sh /julia_cpu_target.sh

ARG CHECK_BOUNDS=auto
ARG ENV_NAME=docs

# Explicitly set the Julia depot path: on GitHub Actions the user's home
# directory may be somewhere else (e.g. `/github`), so we need to be sure we
# have a consistent and persistent depot path.
ENV JULIA_DEPOT_PATH=/usr/local/share/julia:
# Set a default version-independent project.
ENV JULIA_PROJECT='@numericalearth'
# Add the environment to the load path
ENV JULIA_LOAD_PATH=:${JULIA_PROJECT}
# Use eager registry to get latest packages possible from PkgServer
ENV JULIA_PKG_SERVER_REGISTRY_PREFERENCE=eager

# Follow https://github.com/JuliaGPU/CUDA.jl/blob/5d9474ae73fab66989235f7ff4fd447d5ee06f8e/Dockerfile

ARG CUDA_VERSION=13.0
ARG REACTANT_CUDA_VERSION=13.1

# We need a stub `libcuda.so.1` in order to load a CUDA-enabled build of Reactant_jll, but
# an empty shared library with that soname is sufficient.  Install and remove GCC in the
# same step, to avoid caching its entire installation outside of this step.
RUN /bin/sh -c 'export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends gcc libc-dev \
    && gcc -shared -Wl,-soname=libcuda.so.1 -o libcuda.so.1 /dev/null \
    && apt-get remove -y gcc libc-dev \
    && apt-get --purge autoremove -y \
    && apt-get autoclean \
    && rm -rf /var/lib/apt/lists/*'

# Configure the preferences for CUDA_Runtime_jll and Reactant_jll in the `@numericalearth`
# environment, which is in the load path.  The packages need to be listed in the project
# for the preferences to be picked up, but we only put them in `[extras]` for the time
# being, so that we don't have to resolve the environment now: they will be installed
# later with the same versions resolved in the target environment, to avoid installing
# multiple versions or builds of the large `Reactant_jll` and CUDA artifacts.
RUN numericalearth_env=/usr/local/share/julia/environments/numericalearth && \
    mkdir -p "${numericalearth_env}" && \
    printf '[CUDA_Runtime_jll]\nversion = "%s"\n[Reactant_jll]\ngpu = "cuda"\ngpu_version = "%s"\n' \
        "${CUDA_VERSION}" "${REACTANT_CUDA_VERSION}" > "${numericalearth_env}/LocalPreferences.toml" && \
    printf '[extras]\nCUDA_Runtime_jll = "76a88914-d11a-5bdc-97e0-2f5a05c973a2"\nReactant_jll = "0192cb87-2b54-54ad-80e0-3be72ad8a3c0"\n' \
        > "${numericalearth_env}/Project.toml"

# Clone NumericalEarth, instantiate the target environment, install in `@numericalearth` the
# same versions of CUDA and the JLLs resolved in the target environment (they are all
# already in the depot at that point, so nothing is downloaded or compiled twice), and clean
# up the NumericalEarth clone, all within the same step so that we don't cache everything
# that was written in the clone directory.  In particular, the CondaPkg environment would
# occupy lots of space in this layer, needlessly.
RUN git clone --depth=1 https://github.com/NumericalEarth/NumericalEarth.jl /tmp/NumericalEarth.jl && \
    . /julia_cpu_target.sh && LD_LIBRARY_PATH='.' JULIA_PKG_PRECOMPILE_AUTO="false" julia --color=yes \
    --project=/tmp/NumericalEarth.jl/${ENV_NAME} \
    --check-bounds=${CHECK_BOUNDS} -e '#= make bundled depot non-writable (JuliaLang/Pkg.jl#4120) =# \
              bundled_depot = last(DEPOT_PATH); \
              run(`find $bundled_depot/compiled -type f -writable -exec chmod -w \{\} \;`); \
              \
              #= instantiate the target environment =# \
              using Pkg; \
              Pkg.instantiate(); \
              Pkg.precompile(); \
              using CUDA; \
              CUDA.precompile_runtime(); \
              \
              #= install the same versions in `@numericalearth`.  Since CUDA is loaded in this =# \
              #= session, `Pkg.add` will also prefer the loaded versions of its dependencies.   =# \
              #= Read the versions from the whole manifest, not `Pkg.dependencies()`, which    =# \
              #= only lists the packages loadable from the target environment: NumericalEarth  =# \
              #= uses a workspace, so e.g. Reactant_jll is installed also for `test`.          =# \
              #= Keep the `[extras]` in the project, otherwise the preferences would be        =# \
              #= ignored when `Pkg.add` selects the artifacts to download.                     =# \
              versions = Dict(e.name => e.version for e in values(Pkg.Types.EnvCache().manifest)); \
              Pkg.activate("/usr/local/share/julia/environments/numericalearth"); \
              Pkg.add([PackageSpec(; name, version=versions[name]) for name in ("CUDA", "CUDA_Runtime_jll", "Reactant_jll") if haskey(versions, name)]); \
              Pkg.precompile(); \
              \
              #= revert bundled depot changes =# \
              run(`find $bundled_depot/compiled -type f -writable -exec chmod +w \{\} \;`)' && \
    rm -rf /tmp/NumericalEarth.jl

# Remove fake libcuda.so.1
RUN rm -fv libcuda.so.1
