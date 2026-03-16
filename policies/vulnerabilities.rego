package main

deny[msg] {
    input.Results[_].Vulnerabilities[_].Severity == "CRITICAL"
    msg := "Critical vulnerabilities are not allowed"
}

warn[msg] {
    vulns := [v | v := input.Results[_].Vulnerabilities[_]; v.Severity == "HIGH"]
    count(vulns) > 10
    msg := sprintf("High vulnerability count exceeds threshold: %d > 10", [count(vulns)])
}
