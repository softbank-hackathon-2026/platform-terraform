variable "name" {
  description = "Network 리소스 이름의 접두사입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name은 비어 있을 수 없습니다."
  }
}

variable "vpc_cidr" {
  description = "VPC에 사용할 IPv4 CIDR입니다."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr은 유효한 IPv4 CIDR이어야 합니다."
  }
}

variable "public_subnets" {
  description = "논리 이름을 키로 사용하는 Public Subnet 정의입니다."
  type = map(object({
    availability_zone = string
    cidr_block        = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, subnet in var.public_subnets :
      length(trimspace(key)) > 0 &&
      length(trimspace(subnet.availability_zone)) > 0 &&
      can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "public_subnets의 키와 Availability Zone은 비어 있을 수 없고 CIDR은 유효한 IPv4 CIDR이어야 합니다."
  }
}

variable "private_subnets" {
  description = "논리 이름을 키로 사용하는 Private Subnet 정의입니다."
  type = map(object({
    availability_zone = string
    cidr_block        = string
  }))

  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "private_subnets에는 하나 이상의 Subnet이 필요합니다."
  }

  validation {
    condition = alltrue([
      for key, subnet in var.private_subnets :
      length(trimspace(key)) > 0 &&
      length(trimspace(subnet.availability_zone)) > 0 &&
      can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "private_subnets의 키와 Availability Zone은 비어 있을 수 없고 CIDR은 유효한 IPv4 CIDR이어야 합니다."
  }
}

variable "nat_gateway_mode" {
  description = "NAT Gateway 구성 방식입니다. none, regional, zonal을 사용할 수 있습니다."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "regional", "zonal"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode는 none, regional, zonal 중 하나여야 합니다."
  }
}

variable "zonal_nat_subnet_keys" {
  description = "Zonal NAT Gateway를 배치할 Public Subnet의 논리 키를 AZ별로 지정합니다."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for availability_zone, subnet_key in var.zonal_nat_subnet_keys :
      length(trimspace(availability_zone)) > 0 && length(trimspace(subnet_key)) > 0
    ])
    error_message = "zonal_nat_subnet_keys의 Availability Zone과 Public Subnet 키는 비어 있을 수 없습니다."
  }
}

variable "tags" {
  description = "Network 리소스에 적용할 추가 태그입니다."
  type        = map(string)
  default     = {}
}
