variable "waf_rule_groups" {
  type = list(object({
    rule_group_name = string
    rule = list(object({
      id      = string
      enabled = bool
      action  = string
    }))
  }))
}
