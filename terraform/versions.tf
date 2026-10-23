terraform {
  required_version = ">= 1.6, < 2.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    google  = { source = "hashicorp/google", version = "~> 7.0" }
  }
}
provider "aws" { region = "us-east-1" }
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}
provider "google" {
  project = var.gcp_project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}
