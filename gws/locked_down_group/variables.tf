variable "email" {
    type        = string
    description = "The group's email address."
}

variable "name" {
    type        = string
    description = "The group's display name."
}

variable "description" {
    type        = string
    description = "The group's description."
    default     = null
}

variable "who_can_post_message" {
    type        = string
    description = "Who may post (deliver mail) to the group. Defaults to NONE_CAN_POST for a send-as-only identity; set to e.g. ANYONE_CAN_POST when the address must receive replies."
    default     = "NONE_CAN_POST"
}
