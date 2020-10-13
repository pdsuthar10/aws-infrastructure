# variables.tf
variable "access_key" {
  default = "AKIAUS7V3CVLSUSQRMUB"
}
variable "secret_key" {
  default = "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"
}
variable "region" {
  default = "us-east-1"
}
variable "availabilityZone" {
  default = "us-east-1a"
}
variable "instanceTenancy" {
  default = "default"
}
variable "dnsSupport" {
  default = true
}
variable "dnsHostNames" {
  default = true
}
variable "vpcCIDRblock" {
  default = "10.0.0.0/16"
}
variable "subnetCIDRblock" {
  default = "10.0.1.0/24"
}
variable "destinationCIDRblock" {
  default = "0.0.0.0/0"
}
variable "ingressCIDRblock" {
  type = list
  default = [ "0.0.0.0/0" ]
}
variable "egressCIDRblock" {
  type = list
  default = [ "0.0.0.0/0" ]
}
variable "mapPublicIP" {
  default = true
}

variable "subnet_cidrs_public" {
  description = "Subnet CIDRs for public subnets (length must match configured availability_zones)"
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  type = list(string)
}

variable "availability_zones" {
  default = ["us-east-1a","us-east-1b","us-east-1c"]
  type = list(string)
}
# end of variables.tf