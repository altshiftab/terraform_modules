resource "gws_group" "group" {
    email       = var.email
    name        = var.name
    description = var.description
}

# An admin-managed group locked down to its narrowest useful posture: not
# discoverable outside its membership, no self-join, no external members, not in
# the global address list, and members cannot post as the group. By default
# nobody can post to it (who_can_post_message = NONE_CAN_POST), which suits a
# send-as-only identity that never receives mail. For an address that must
# receive replies, set var.who_can_post_message accordingly (e.g.
# ANYONE_CAN_POST) — otherwise inbound mail is silently rejected.
#
# Google only permits NONE_CAN_POST together with archive-only mode, so
# archive_only is enabled automatically when posting is set to NONE_CAN_POST.
resource "gws_group_settings" "group" {
    group_email = gws_group.group.email

    who_can_join                   = "INVITED_CAN_JOIN"
    who_can_post_message           = var.who_can_post_message
    archive_only                   = var.who_can_post_message == "NONE_CAN_POST" ? "true" : "false"
    who_can_view_group             = "ALL_MANAGERS_CAN_VIEW"
    who_can_view_membership        = "ALL_MANAGERS_CAN_VIEW"
    who_can_discover_group         = "ALL_MEMBERS_CAN_DISCOVER"
    who_can_contact_owner          = "ALL_MANAGERS_CAN_CONTACT"
    who_can_leave_group            = "NONE_CAN_LEAVE"
    allow_external_members         = "false"
    allow_web_posting              = "false"
    include_in_global_address_list = "false"
    members_can_post_as_the_group  = "false"
    enable_collaborative_inbox     = "false"
}
