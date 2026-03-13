# syntax=docker/dockerfile:1
ARG JULIA_VERSION=1.12.5
FROM julia:${JULIA_VERSION}

# Install some dependencies
RUN /bin/sh -c 'export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y ca-certificates earlyoom gcc git gpg jq \
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

# Follow https://github.com/JuliaGPU/CUDA.jl/blob/5d9474ae73fab66989235f7ff4fd447d5ee06f8e/Dockerfile

ARG CUDA_VERSION=13.0
ARG REACTANT_CUDA_VERSION=13.1

# We need a stub `libcuda.so.1` in order to load a CUDA-enabled build of Reactant_jll, but
# an empty shared library with that soname is sufficient.  Yes, I'm evil.
RUN gcc -shared -Wl,-soname=libcuda.so.1 -o libcuda.so.1 /dev/null

# pre-install the CUDA toolkit from an artifact. we do this separately from CUDA.jl so that
# this layer can be cached independently. it also avoids double precompilation of CUDA.jl in
# order to call `CUDA.set_runtime_version!`.
# Note: we first install install `Reactant` & `Reactant_jll` to resolve the environment
# together, and then remove `Reactant` because we don't need it at this stage, and finally
# we precompile the environment.  This should hopefully avoid installing two large
# `Reactant_jll` artifacts when we later instantiate the environment.
RUN . /julia_cpu_target.sh && JULIA_PKG_PRECOMPILE_AUTO="false" julia --color=yes --check-bounds=${CHECK_BOUNDS} -e '#= make bundled depot non-writable (JuliaLang/Pkg.jl#4120) =# \
              bundled_depot = last(DEPOT_PATH); \
              run(`find $bundled_depot/compiled -type f -writable -exec chmod -w \{\} \;`); \
              #= configure the preference =# \
              env = "/usr/local/share/julia/environments/numericalearth"; \
              mkpath(env); \
              write("$env/LocalPreferences.toml", \
                    "[CUDA_Runtime_jll]\nversion = \"'${CUDA_VERSION}'\"\n[Reactant_jll]\ngpu = \"cuda\"\ngpu_version = \"'${REACTANT_CUDA_VERSION}'\""); \
              \
              #= install the JLLs =# \
              using Pkg; \
              Pkg.add(["CUDA_Runtime_jll", "Reactant_jll", "Reactant"]); \
              Pkg.rm("Reactant"); \
              Pkg.precompile(); \
              #= revert bundled depot changes =# \
              run(`find $bundled_depot/compiled -type f -writable -exec chmod +w \{\} \;`)'

# install CUDA.jl itself
RUN . /julia_cpu_target.sh && julia --color=yes --check-bounds=${CHECK_BOUNDS} -e 'using Pkg; Pkg.add("CUDA"); \
    using CUDA; CUDA.precompile_runtime()'

# Clone NumericalEarth
RUN git clone --depth=1 https://github.com/NumericalEarth/NumericalEarth.jl /tmp/NumericalEarth.jl

# Instantiate environment
# NumericalEarth.jl has no test/Project.toml — test deps are in main [extras].
# For ENV_NAME=test: use --project=/tmp/NumericalEarth.jl (main project)
# For ENV_NAME=docs: use --project=/tmp/NumericalEarth.jl/docs (has its own Project.toml)
RUN . /julia_cpu_target.sh && LD_LIBRARY_PATH='.' julia --color=yes \
    --project=/tmp/NumericalEarth.jl/$([ "${ENV_NAME}" = "test" ] && echo "" || echo "${ENV_NAME}") \
    --check-bounds=${CHECK_BOUNDS} -e 'using Pkg; Pkg.instantiate()'

# Clean up NumericalEarth clone
RUN rm -rf /tmp/NumericalEarth.jl

# Remove fake libcuda.so.1
RUN rm -fv libcuda.so.1

# Uninstall packages not needed at runtime, to reduce size of image
RUN /bin/sh -c 'export DEBIAN_FRONTEND=noninteractive \
    && apt-get remove --autoremove -y gcc \
    && apt-get --purge autoremove -y \
    && apt-get autoclean \
    && rm -rf /var/lib/apt/lists/*'