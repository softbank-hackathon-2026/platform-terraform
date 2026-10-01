mock_provider "aws" {
  override_during = plan

  mock_resource "aws_internet_gateway" {
    defaults = { id = "igw-public-only" }
  }

  mock_resource "aws_route_table" {
    defaults = { id = "rtb-public-only" }
  }
}

variables {
  name     = "sample-public-only"
  vpc_cidr = "10.10.0.0/16"
  public_subnets = {
    web_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.10.0.0/24" }
    web_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.10.1.0/24" }
  }
}

run "omitted_private_subnets" {
  command = plan

  assert {
    condition = (
      length(aws_subnet.public) == 2 &&
      length(aws_route_table.public) == 1 &&
      length(aws_route_table_association.public) == 2 &&
      length(aws_internet_gateway.this) == 1 &&
      length(aws_route.public_internet) == 1 &&
      aws_route.public_internet[0].destination_cidr_block == "0.0.0.0/0" &&
      aws_route.public_internet[0].gateway_id == aws_internet_gateway.this[0].id &&
      aws_route.public_internet[0].route_table_id == aws_route_table.public[0].id
    )
    error_message = "Private 입력을 생략해도 Public Subnet과 Internet Gateway 기본 경로가 연결되어야 합니다."
  }

  assert {
    condition = (
      length(aws_subnet.private) == 0 &&
      length(aws_route_table.private) == 0 &&
      length(aws_route_table_association.private) == 0 &&
      length(aws_nat_gateway.regional) == 0 &&
      length(aws_nat_gateway.zonal) == 0 &&
      length(aws_eip.zonal) == 0 &&
      length(aws_route.private_regional) == 0 &&
      length(aws_route.private_zonal) == 0 &&
      length(output.private_subnet_ids) == 0 &&
      length(output.private_route_table_ids) == 0 &&
      length(output.nat_gateway_ids_by_az) == 0
    )
    error_message = "Public 전용 기본 구성에는 Private Subnet, Private 경로, NAT와 EIP가 없어야 합니다."
  }
}

run "explicit_empty_private_subnets" {
  command = plan

  variables {
    private_subnets = {}
  }

  assert {
    condition = (
      length(aws_subnet.public) == 2 &&
      length(output.private_subnet_ids) == 0 &&
      length(output.private_route_table_ids) == 0 &&
      length(aws_nat_gateway.regional) == 0 &&
      length(aws_nat_gateway.zonal) == 0
    )
    error_message = "빈 private_subnets Map은 허용되고 Private Subnet과 NAT를 생성하지 않아야 합니다."
  }
}

run "rejects_invalid_private_cidr" {
  command = plan

  variables {
    private_subnets = {
      app_a = { availability_zone = "ap-northeast-2a", cidr_block = "invalid-cidr" }
    }
  }

  expect_failures = [var.private_subnets]
}
