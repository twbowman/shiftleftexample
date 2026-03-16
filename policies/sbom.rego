package main

deny[msg] {
    not input.components
    msg := "SBOM must contain components"
}

deny[msg] {
    count(input.components) == 0
    msg := "SBOM must contain at least one component"
}

deny[msg] {
    not input.metadata
    msg := "SBOM must contain metadata"
}
