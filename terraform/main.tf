variable "name" {
  type        = string
  description = "Globally unique lowercase letters and digits, 8 to 18 characters"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{7,17}$", var.name))
    error_message = "Use 8 to 18 lowercase letters and digits, starting with a letter."
  }
}
variable "admin_cidr" { type = string }
variable "ssh_public_key_path" { type = string }
variable "azure_subscription_id" { type = string }
variable "gcp_project_id" { type = string }
module "aws" {
  source     = "./modules/aws"
  name       = var.name
  admin_cidr = var.admin_cidr
  ssh_key    = file(pathexpand(var.ssh_public_key_path))
  startup    = file("${path.module}/../bootstrap/aws.sh")
}
module "azure" {
  source     = "./modules/azure"
  name       = var.name
  admin_cidr = var.admin_cidr
  ssh_key    = file(pathexpand(var.ssh_public_key_path))
  startup    = file("${path.module}/../bootstrap/azure.sh")
}
module "gcp" {
  source     = "./modules/gcp"
  name       = var.name
  admin_cidr = var.admin_cidr
  ssh_key    = file(pathexpand(var.ssh_public_key_path))
  startup    = file("${path.module}/../bootstrap/gcp.sh")
}
output "origin_ips" {
  value = { aws = module.aws.ip, azure = module.azure.ip, gcp = module.gcp.ip }
}
output "storage" {
  value = { aws = module.aws.bucket, azure = module.azure.account, gcp = module.gcp.bucket }
}
