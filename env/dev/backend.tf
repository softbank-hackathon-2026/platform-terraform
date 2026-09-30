terraform {
  backend "s3" {
    profile      = "sbh-platform"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
