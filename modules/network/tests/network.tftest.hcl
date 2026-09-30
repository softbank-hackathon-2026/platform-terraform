mock_provider "aws" {
  override_during = plan
}

variables {
  name     = "sample-test"
  vpc_cidr = "10.10.0.0/16"

  private_subnets = {
    app_a = {
      availability_zone = "ap-northeast-2a"
      cidr_block        = "10.10.10.0/24"
    }
    app_c = {
      availability_zone = "ap-northeast-2c"
      cidr_block        = "10.10.11.0/24"
    }
  }
}

run "none" {
  command = plan

  assert {
    condition     = length(aws_route_table.private) == 2
    error_message = "Private Subnet마다 Route Table이 필요합니다."
  }

  assert {
    condition = (
      length(aws_internet_gateway.this) == 0 &&
      length(aws_eip.zonal) == 0 &&
      length(aws_nat_gateway.regional) == 0 &&
      length(aws_nat_gateway.zonal) == 0 &&
      length(aws_route.private_regional) == 0 &&
      length(aws_route.private_zonal) == 0
    )
    error_message = "none 모드에서는 Internet Gateway, NAT, EIP, Private 기본 경로를 생성하면 안 됩니다."
  }
}

run "regional" {
  command = plan

  override_resource {
    target          = aws_nat_gateway.regional[0]
    override_during = plan
    values = {
      id = "nat-regional"
    }
  }

  variables {
    nat_gateway_mode = "regional"
  }

  assert {
    condition = (
      length(aws_internet_gateway.this) == 1 &&
      length(aws_nat_gateway.regional) == 1 &&
      length(aws_nat_gateway.zonal) == 0 &&
      length(aws_eip.zonal) == 0 &&
      length(aws_route.private_regional) == 2
    )
    error_message = "regional 모드에서는 Regional NAT 하나와 Private Subnet별 기본 경로가 필요합니다."
  }

  assert {
    condition     = aws_nat_gateway.regional[0].availability_mode == "regional"
    error_message = "Regional NAT Gateway의 availability_mode가 regional이어야 합니다."
  }

  assert {
    condition = alltrue([
      for route in values(aws_route.private_regional) :
      route.nat_gateway_id == aws_nat_gateway.regional[0].id
    ])
    error_message = "모든 Regional Private Route가 같은 NAT Gateway를 사용해야 합니다."
  }
}

run "zonal_explicit_subnet" {
  command = plan

  override_resource {
    target          = aws_subnet.public["nat_a"]
    override_during = plan
    values = {
      id = "subnet-nat-a"
    }
  }

  override_resource {
    target          = aws_subnet.public["nat_c"]
    override_during = plan
    values = {
      id = "subnet-nat-c"
    }
  }

  override_resource {
    target          = aws_nat_gateway.zonal["ap-northeast-2a"]
    override_during = plan
    values = {
      id = "nat-zonal-a"
    }
  }

  override_resource {
    target          = aws_nat_gateway.zonal["ap-northeast-2c"]
    override_during = plan
    values = {
      id = "nat-zonal-c"
    }
  }

  variables {
    nat_gateway_mode = "zonal"

    public_subnets = {
      public_a = {
        availability_zone = "ap-northeast-2a"
        cidr_block        = "10.10.0.0/24"
      }
      nat_a = {
        availability_zone = "ap-northeast-2a"
        cidr_block        = "10.10.1.0/24"
      }
      nat_c = {
        availability_zone = "ap-northeast-2c"
        cidr_block        = "10.10.2.0/24"
      }
    }

    zonal_nat_subnet_keys = {
      "ap-northeast-2a" = "nat_a"
      "ap-northeast-2c" = "nat_c"
    }
  }

  assert {
    condition = (
      length(aws_eip.zonal) == 2 &&
      length(aws_nat_gateway.zonal) == 2 &&
      length(aws_nat_gateway.regional) == 0 &&
      length(aws_route.private_zonal) == 2
    )
    error_message = "zonal 모드에서는 Private Subnet AZ마다 EIP, NAT, 기본 경로가 필요합니다."
  }

  assert {
    condition = (
      aws_nat_gateway.zonal["ap-northeast-2a"].subnet_id == aws_subnet.public["nat_a"].id &&
      aws_nat_gateway.zonal["ap-northeast-2c"].subnet_id == aws_subnet.public["nat_c"].id
    )
    error_message = "Zonal NAT Gateway가 사용자가 선택한 Public Subnet에 생성되어야 합니다."
  }

  assert {
    condition = (
      aws_route.private_zonal["app_a"].nat_gateway_id == aws_nat_gateway.zonal["ap-northeast-2a"].id &&
      aws_route.private_zonal["app_c"].nat_gateway_id == aws_nat_gateway.zonal["ap-northeast-2c"].id
    )
    error_message = "Private Route가 같은 AZ의 Zonal NAT Gateway를 사용해야 합니다."
  }
}

run "rejects_invalid_mode" {
  command = plan

  variables {
    nat_gateway_mode = "shared"
  }

  expect_failures = [
    var.nat_gateway_mode,
  ]
}

run "rejects_unknown_zonal_subnet" {
  command = plan

  variables {
    nat_gateway_mode = "zonal"

    public_subnets = {
      nat_a = {
        availability_zone = "ap-northeast-2a"
        cidr_block        = "10.10.0.0/24"
      }
      nat_c = {
        availability_zone = "ap-northeast-2c"
        cidr_block        = "10.10.1.0/24"
      }
    }

    zonal_nat_subnet_keys = {
      "ap-northeast-2a" = "missing"
      "ap-northeast-2c" = "nat_c"
    }
  }

  expect_failures = [
    aws_vpc.this,
  ]
}

run "rejects_missing_zonal_az" {
  command = plan

  variables {
    nat_gateway_mode = "zonal"

    public_subnets = {
      nat_a = {
        availability_zone = "ap-northeast-2a"
        cidr_block        = "10.10.0.0/24"
      }
    }

    zonal_nat_subnet_keys = {
      "ap-northeast-2a" = "nat_a"
    }
  }

  expect_failures = [
    aws_vpc.this,
  ]
}

run "rejects_zonal_az_mismatch" {
  command = plan

  variables {
    nat_gateway_mode = "zonal"

    public_subnets = {
      nat_a = {
        availability_zone = "ap-northeast-2a"
        cidr_block        = "10.10.0.0/24"
      }
      nat_c = {
        availability_zone = "ap-northeast-2c"
        cidr_block        = "10.10.1.0/24"
      }
    }

    zonal_nat_subnet_keys = {
      "ap-northeast-2a" = "nat_c"
      "ap-northeast-2c" = "nat_c"
    }
  }

  expect_failures = [
    aws_vpc.this,
  ]
}
