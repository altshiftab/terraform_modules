data "external" "expanded_ipv6" {
    program = ["python", "${path.module}/expand_ipv6.py"]

    query = {
        ipv6 = var.ipv6
    }
}

output "expanded" {
    value = data.external.expanded_ipv6.result["expanded"]
}
