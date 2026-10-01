provider "aws" {
  profile = "sbh-platform"
  region  = "ap-northeast-2"

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias   = "us_east_1"
  profile = "sbh-platform"
  region  = "us-east-1"
}
