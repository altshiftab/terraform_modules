output "group" {
    value       = gws_group.group
    description = "The managed gws_group resource."
}

output "settings" {
    value       = gws_group_settings.group
    description = "The managed gws_group_settings resource."
}

output "email" {
    value       = gws_group.group.email
    description = "The group's email address."
}
