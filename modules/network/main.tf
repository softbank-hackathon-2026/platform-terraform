locals {
  all_subnet_cidrs = concat(
    [for subnet in values(var.public_subnets) : subnet.cidr_block],
    [for subnet in values(var.private_subnets) : subnet.cidr_block]
  )

  nat_private_subnets = {
    for key, subnet in var.private_subnets : key => subnet if subnet.enable_nat_route
  }

  private_availability_zones = toset([
    for subnet in values(local.nat_private_subnets) : subnet.availability_zone
  ])

  create_internet_gateway = length(var.public_subnets) > 0 || var.nat_gateway_mode != "none"

  zonal_nat_subnet_keys_exist = alltrue([
    for subnet_key in values(var.zonal_nat_subnet_keys) :
    contains(keys(var.public_subnets), subnet_key)
  ])

  zonal_nat_availability_zones_match = !local.zonal_nat_subnet_keys_exist || alltrue([
    for availability_zone, subnet_key in var.zonal_nat_subnet_keys :
    try(var.public_subnets[subnet_key].availability_zone == availability_zone, false)
  ])

  zonal_nat_covers_private_availability_zones = (
    length(setsubtract(toset(keys(var.zonal_nat_subnet_keys)), local.private_availability_zones)) == 0 &&
    length(setsubtract(local.private_availability_zones, toset(keys(var.zonal_nat_subnet_keys)))) == 0
  )

  zonal_nat_configuration_valid = (
    var.nat_gateway_mode == "zonal" &&
    local.zonal_nat_subnet_keys_exist &&
    local.zonal_nat_availability_zones_match &&
    local.zonal_nat_covers_private_availability_zones
  )

  active_zonal_nat_subnet_keys = local.zonal_nat_configuration_valid ? var.zonal_nat_subnet_keys : tomap({})
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-shared"
  })

  lifecycle {
    precondition {
      condition     = length(distinct(local.all_subnet_cidrs)) == length(local.all_subnet_cidrs)
      error_message = "Public Subnet과 Private Subnet의 CIDR은 중복될 수 없습니다."
    }

    precondition {
      condition     = var.nat_gateway_mode == "zonal" || length(var.zonal_nat_subnet_keys) == 0
      error_message = "zonal_nat_subnet_keys는 zonal 모드에서만 사용할 수 있습니다."
    }

    precondition {
      condition     = var.nat_gateway_mode != "zonal" || local.zonal_nat_subnet_keys_exist
      error_message = "zonal_nat_subnet_keys에 존재하지 않는 Public Subnet 키가 있습니다."
    }

    precondition {
      condition     = var.nat_gateway_mode != "zonal" || local.zonal_nat_availability_zones_match
      error_message = "Zonal NAT Gateway의 AZ와 선택한 Public Subnet의 AZ가 일치해야 합니다."
    }

    precondition {
      condition     = var.nat_gateway_mode != "zonal" || local.zonal_nat_covers_private_availability_zones
      error_message = "zonal_nat_subnet_keys는 enable_nat_route가 true인 Private Subnet AZ를 정확히 포함해야 합니다."
    }
  }
}

resource "aws_internet_gateway" "this" {
  count = local.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw-shared"
  })
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-subnet-${replace(each.key, "_", "-")}"
  })
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-subnet-${replace(each.key, "_", "-")}"
  })
}

resource "aws_route_table" "public" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
  route_table_id         = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  route_table_id = aws_route_table.public[0].id
  subnet_id      = each.value.id
}

resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-rt-${replace(each.key, "_", "-")}"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = each.value.id
}

resource "aws_nat_gateway" "regional" {
  count = var.nat_gateway_mode == "regional" ? 1 : 0

  availability_mode = "regional"
  connectivity_type = "public"
  vpc_id            = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-nat-regional"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_eip" "zonal" {
  for_each = local.active_zonal_nat_subnet_keys

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-eip-nat-${replace(each.value, "_", "-")}"
  })
}

resource "aws_nat_gateway" "zonal" {
  for_each = local.active_zonal_nat_subnet_keys

  allocation_id     = aws_eip.zonal[each.key].id
  availability_mode = "zonal"
  connectivity_type = "public"
  subnet_id         = aws_subnet.public[each.value].id

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${replace(each.value, "_", "-")}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_regional" {
  for_each = var.nat_gateway_mode == "regional" ? local.nat_private_subnets : {}

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.regional[0].id
  route_table_id         = aws_route_table.private[each.key].id
}

resource "aws_route" "private_zonal" {
  for_each = local.zonal_nat_configuration_valid ? local.nat_private_subnets : {}

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.zonal[each.value.availability_zone].id
  route_table_id         = aws_route_table.private[each.key].id
}
