# Stage 1: Build

Builds a Docker image from source and optionally saves it as a tarball for downstream pipeline stages.

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 1
./pipeline.sh --stage 1 --tag myapp:1.0.0
./pipeline.sh --stage 1 --target ./myapp --tag myapp:1.0.0
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 1
.\pipeline.ps1 -Stage 1 -Tag myapp:1.0.0
.\pipeline.ps1 -Stage 1 -Target ./myapp -Tag myapp:1.0.0
```

## Run via Docker

```bash
# Build from workspace (mount Docker socket for docker-in-docker)
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)":/workspace \
    -v "$(pwd)/artifacts":/artifacts \
    DockerShiftLeft/stage1-build:latest \
    --context /workspace --tag myapp:1.0.0 --output /artifacts/stage1

# Build with custom Dockerfile
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)":/workspace \
    -v "$(pwd)/artifacts":/artifacts \
    DockerShiftLeft/stage1-build:latest \
    --context /workspace --dockerfile /workspace/docker/Dockerfile --tag myapp:1.0.0

# Build with build args
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)":/workspace \
    DockerShiftLeft/stage1-build:latest \
    --context /workspace --tag myapp:1.0.0 --build-arg VERSION=1.0 --build-arg ENV=prod

# Build without cache
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)":/workspace \
    DockerShiftLeft/stage1-build:latest \
    --context /workspace --tag myapp:1.0.0 --no-cache
```

## Script Options

| Flag | Description |
|------|-------------|
| `-c, --context <dir>` | Build context path (default: `/workspace`) |
| `-f, --dockerfile <path>` | Path to Dockerfile (default: `<context>/Dockerfile`) |
| `-t, --tag <tag>` | Image tag (default: `app:latest`) |
| `-o, --output <dir>` | Save image tarball to this directory |
| `-a, --build-arg <arg>` | Build argument (`KEY=VALUE`), can be repeated |
| `--no-cache` | Disable Docker build cache |
| `-h, --help` | Show help |

## Artifacts

When `--output` is specified:

```
<output>/
├── <tag>.tar              # Image saved as tarball
└── build-metadata.json    # Build metadata (tag, context, timing)
```

The tarball can be loaded by Stage 3 for vulnerability scanning without needing the image in the local Docker daemon.

## Debugging & Interactive Testing

To drop into the container with a shell for debugging or testing tools directly:

```bash
# Interactive shell with Docker socket and workspace mounted
docker run --rm -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)":/workspace \
    --entrypoint bash \
    DockerShiftLeft/stage1-build:latest

# Once inside, test Docker commands:
docker version
docker build -t test:latest /workspace
docker images

# Inspect a built image
docker image inspect test:latest --format '{{.Architecture}} {{.Os}} {{.Size}}'

# Test saving an image tarball
docker save test:latest -o /tmp/test.tar
ls -lh /tmp/test.tar
```
