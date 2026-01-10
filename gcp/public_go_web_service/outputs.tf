output "service" {
  description = "The web service interface used by the LB and DNS."
  value = {
    domain_names            = module.web_service.domain_names
    backend_service         = module.web_service.backend_service
  }
}
