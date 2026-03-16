# Stage 1: Build

Builds a container image from a Dockerfile and optionally saves it as a tarball for downstream pipeline stages.

## Usage

### Native (requires Docker)

```bash
./build.sh --context ./myapp --tag myapp:1.0.0
```

### Docker

```bash
# Build the stage1 image
docker build -t stage1-build ./stage1-build

# Run a build (mount Docker socket + workspace)
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)":/workspace \
    -v "$(pwd)/artifacts":/artifacts \
    stage1-build \
    --context /workspace/myapp \
    --tag myapp:1.0.0 \
    --output /artifacts/stage1
```

### GitHub Actions

```yaml
- name: Stage 1 - Build
  run: |
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${{ github.workspace }}:/workspace \
      -v ${{ github.workspace }}/artifacts:/artifacts \
      stage1-build \
      --context /workspace \
      --tag ${{ github.repository }}:${{ github.sha }} \
      --output /artifacts/stage1
```

## Options

| Flag | Description |
|------|-------------|
| `-c, --context <dir>` | Build context path (default: `/workspace`) |
| `-f, --dockerfile <path>` | Path to Dockerfile (default: `<context>/Dockerfile`) |
| `-t, --tag <tag>` | Image tag (default: `app:latest`) |
| `-o, --output <dir>` | Save image tarball to this directory |
| `-a, --build-arg <arg>` | Build argument (KEY=VALUE), can be repeated |
| `--no-cache` | Disable build cache |

## Artifacts

When `--output` is specified, the stage produces:

```
<output>/
├── <image_tag>.tar       # Image tarball (loadable with docker load)
└── build-metadata.json   # Build metadata for downstream stages
```

### build-metadata.json

```json
{
    "image_tag": "myapp:1.0.0",
    "tarball": "/artifacts/stage1/myapp_1.0.0.tar",
    "build_context": "/workspace/myapp",
    "dockerfile": "/workspace/myapp/Dockerfile",
    "build_time_seconds": 45,
    "timestamp": "2024-01-15T10:30:00Z"
}
```

Downstream stages can read this to know what image to scan/sign.
