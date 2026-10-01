provider "aws" {
  profile = "sbh-platform"
  region  = "ap-northeast-2"

  default_tags {
    tags = local.tags
  }
}
