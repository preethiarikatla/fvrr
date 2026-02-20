variable "waf_exclusions" {
  type = list(object({
    match_variable = string
    operator       = string
    selector       = string
  }))
}
