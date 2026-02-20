terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.50.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  config = yamldecode(file("${path.module}/values.yaml"))
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-waf-test"
  location = "eastus"
}

resource "azurerm_web_application_firewall_policy" "waf" {
  name                = "test-waf-policy"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    # 🔴 This is where [] vs null matters
    dynamic "exclusion" {
      for_each = local.config.waf_exclusions
      content {
        match_variable = exclusion.value.match_variable
        operator       = exclusion.value.operator
        selector       = exclusion.value.selector
      }
    }
  }
}
