# Corporate Certificates

Place your corporate CA certificate(s) in this directory as PEM files.

The build script (`build-all.sh`) expects a file named `corporate-ca.crt` here.
It will be copied into each stage's build context automatically during image builds.
