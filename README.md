# Docker images for NumericalEarth.jl

This repo contains [Docker images](https://github.com/NumericalEarth/numerical-earth-docker-images/pkgs/container/numerical-earth-docker-images) to be used for the Julia package [`NumericalEarth.jl`](https://github.com/NumericalEarth/NumericalEarth.jl).

## `Dockerfile`

The [`Dockerfile`](./Dockerfile) precompiles environments of `NumericalEarth.jl` (`docs` and `test`), used to speed up continuous integration (CI) jobs, with [`CUDA.jl`](https://github.com/JuliaGPU/CUDA.jl) configured to target GPUs.

## Deployment

A [GitHub Actions workflow](./.github/workflows/DockerPublish.yml) builds two images on regular (non-GPU) GitHub-hosted runners:

* `ghcr.io/numericalearth/numerical-earth-docker-images:docs-julia_<version>` to precompile the `docs` environment with the Julia flag `--check-bounds=auto`
* `ghcr.io/numericalearth/numerical-earth-docker-images:test-julia_<version>` to precompile the `test` environment with the Julia flag `--check-bounds=yes`

### For `NumericalEarth.jl` developers: trigger deployments

A new deployment is done automatically on schedule twice a week, to keep the images up-to-date.
If for some reason you want to force a new deployment (e.g. to get updated packages in the image), go to the [workflow page](https://github.com/NumericalEarth/numerical-earth-docker-images/actions/workflows/DockerPublish.yml), and click on the "Run workflow" button.
