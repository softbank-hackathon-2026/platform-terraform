output "vpc_id" {
  description = "생성된 VPC ID입니다."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "생성된 VPC의 IPv4 CIDR입니다."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "논리 이름을 키로 하는 Public Subnet ID Map입니다."
  value = {
    for key, subnet in aws_subnet.public : key => subnet.id
  }
}

output "private_subnet_ids" {
  description = "논리 이름을 키로 하는 Private Subnet ID Map입니다."
  value = {
    for key, subnet in aws_subnet.private : key => subnet.id
  }
}

output "public_route_table_id" {
  description = "Public Route Table ID입니다. Public Subnet이 없으면 null입니다."
  value       = try(aws_route_table.public[0].id, null)
}

output "private_route_table_ids" {
  description = "Private Subnet 논리 이름을 키로 하는 Route Table ID Map입니다."
  value = {
    for key, route_table in aws_route_table.private : key => route_table.id
  }
}

output "nat_gateway_ids_by_az" {
  description = "Availability Zone을 키로 하는 NAT Gateway ID Map입니다."
  value = merge(
    var.nat_gateway_mode == "regional" ? {
      for availability_zone in local.private_availability_zones :
      availability_zone => aws_nat_gateway.regional[0].id
    } : {},
    {
      for availability_zone, nat_gateway in aws_nat_gateway.zonal :
      availability_zone => nat_gateway.id
    }
  )
}
