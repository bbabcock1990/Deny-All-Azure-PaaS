terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}
