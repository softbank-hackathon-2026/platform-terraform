#!/usr/bin/env python3
"""Check dev infrastructure and CI/CD handoff in mock plans."""

import hashlib
import json
import re
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_plan(plan, port, health_path):
    resources = {
        r["address"]: r for r in plan["resource_changes"] if r["mode"] == "managed"
    }

    def attrs(address):
        require(address in resources, f"Missing resource: {address}")
        return resources[address]["change"]["after"]

    def of_type(kind):
        return [r for r in resources.values() if r["type"] == kind]

    taggable = {
        "aws_vpc", "aws_internet_gateway", "aws_subnet", "aws_route_table", "aws_nat_gateway",
        "aws_eip", "aws_lb", "aws_lb_target_group", "aws_lb_listener", "aws_security_group",
        "aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_egress_rule",
        "aws_db_subnet_group", "aws_db_instance", "aws_ecs_cluster", "aws_cloudwatch_log_group",
        "aws_iam_role", "aws_iam_policy",
        "aws_ecr_repository", "aws_s3_bucket",
        "aws_cloudfront_distribution", "aws_cloudfront_vpc_origin", "aws_cloudfront_function",
        "aws_acm_certificate", "aws_ssm_parameter", "aws_secretsmanager_secret",
    }
    required_tags = {
        "Project": "SBH", "Scope": "platform", "Environment": "dev",
        "ManagedBy": "terraform", "Owner": "정호원",
    }
    native_name_fields = {
        "aws_lb": "name", "aws_lb_target_group": "name", "aws_security_group": "name",
        "aws_iam_role": "name", "aws_iam_policy": "name", "aws_ecr_repository": "name",
        "aws_ecs_cluster": "name", "aws_cloudwatch_log_group": "name",
        "aws_cloudfront_function": "name",
        "aws_db_instance": "identifier", "aws_db_subnet_group": "name", "aws_s3_bucket": "bucket",
        "aws_secretsmanager_secret": "name",
    }
    for resource in resources.values():
        if resource["type"] not in taggable:
            continue
        tags = resource["change"]["after"].get("tags")
        require(isinstance(tags, dict), f"Missing resource tags: {resource['address']}")
        require(all(tags.get(key) == value for key, value in required_tags.items()), f"Required tags mismatch: {resource['address']}")
        require(all(value and value.strip() for value in tags.values()), f"Empty tag value: {resource['address']}")
        require(re.fullmatch(r"sbh-platform-dev-[a-z0-9]+(?:-[a-z0-9]+)*", tags.get("Name", "")), f"Invalid Name tag: {resource['address']}")
        field = native_name_fields.get(resource["type"])
        if field:
            require(tags["Name"] == resource["change"]["after"][field], f"Name tag differs from AWS name: {resource['address']}")

    require(len(of_type("aws_subnet")) == 4, "Expected four private subnets and no public subnets")
    require(len(of_type("aws_nat_gateway")) == 1, "Expected one Regional NAT gateway")
    require(len(of_type("aws_eip")) == 0, "Regional NAT must not have Terraform-managed EIPs")
    require(len(of_type("aws_internet_gateway")) == 1, "Regional NAT and CloudFront VPC origin need an internet gateway")
    require(len(of_type("aws_route_table")) == 4, "Expected four private route tables and no public route table")
    require(len(of_type("aws_route_table_association")) == 4, "Expected four private route table associations")
    for tier, base in [("app", 10), ("db", 20)]:
        for offset, az in enumerate(["a", "c"]):
            subnet = attrs(f'module.network.aws_subnet.private["{tier}_{az}"]')
            require(subnet["cidr_block"] == f"10.20.{base + offset}.0/24", "Subnet CIDR mismatch")
            require(subnet["availability_zone"] == f"ap-northeast-2{az}", "Subnet AZ mismatch")
            require(subnet["map_public_ip_on_launch"] is False, "Public IP must be disabled")
    require(len(of_type("aws_route")) == 2, "Only app subnets may have default routes")
    nat = attrs("module.network.aws_nat_gateway.regional[0]")
    require(nat["availability_mode"] == "regional" and nat["connectivity_type"] == "public", "Expected public Regional NAT")
    require(nat["subnet_id"] is None and nat["allocation_id"] is None, "Regional NAT must not use a public subnet or EIP input")
    for az in ["a", "c"]:
        route = attrs(f'module.network.aws_route.private_regional["app_{az}"]')
        require(route["nat_gateway_id"] == "nat-regional", "Both app routes must use the Regional NAT")

    db = attrs("module.database.aws_db_instance.primary")
    require(len(of_type("aws_db_instance")) == 1, "Standby must not be modeled as a read replica")
    require(db["db_name"] == "freesia", "RDS initial database name must be freesia")
    for key, value in {
        "engine": "postgres", "engine_version": "17.11", "instance_class": "db.t4g.small",
        "multi_az": True, "storage_type": "gp3", "allocated_storage": 20,
        "storage_encrypted": True, "publicly_accessible": False,
        "backup_retention_period": 7, "deletion_protection": True,
        "skip_final_snapshot": False, "manage_master_user_password": None,
        "copy_tags_to_snapshot": True,
    }.items():
        require(db.get(key) == value, f"RDS {key} mismatch")
    require(db.get("password") is None and db.get("password_wo") is None, "No DB password may be stored")
    require(attrs("module.database.aws_db_subnet_group.this")["subnet_ids"] == ["subnet-db-a", "subnet-db-c"], "RDS must use DB subnets only")
    require(len(of_type("aws_secretsmanager_secret")) == 1 and len(of_type("aws_secretsmanager_secret_version")) == 1, "Only the DB administrator Secret and its initial Version may be managed")
    master_secret = attrs("module.database.aws_secretsmanager_secret.master[0]")
    master_version = attrs("module.database.aws_secretsmanager_secret_version.master[0]")
    require(master_secret["name"] == "sbh-platform-dev-rds-postgres-master", "Administrator Secret naming mismatch")
    require(master_version["secret_id"] == master_secret["id"], "Administrator Version must belong to the managed Secret")
    require(all(master_version.get(key) is None for key in ["secret_string", "secret_binary", "secret_string_wo"]), "No Secret body may be stored in the plan")
    require(master_version["secret_string_wo_version"] == int(hashlib.sha256(b"dbadmin").hexdigest()[:13], 16), "Secret bootstrap version must match the administrator username")
    require(db["password_wo_version"] == int(hashlib.sha256(master_version["version_id"].encode()).hexdigest()[:13], 16), "DB password version must follow the created Secret Version")
    for counter in [master_version["secret_string_wo_version"], db["password_wo_version"]]:
        require(0 <= counter < 2**53 and int(float(counter)) == counter, "Write-only versions must survive floating-point numeric conversion exactly")
    require(not of_type("aws_secretsmanager_secret_rotation"), "Automatic password rotation is outside the approved dev scope")
    require(len(of_type("aws_ssm_parameter")) == 1, "Expected only the DATABASE_URL parameter")
    parameter = attrs("aws_ssm_parameter.database_url")
    require(parameter["name"] == "/sbh/platform/demo/backend/DATABASE_URL", "DATABASE_URL parameter path mismatch")
    require(parameter["type"] == "SecureString" and parameter["tier"] == "Standard", "DATABASE_URL must be a Standard SecureString")
    require(parameter["data_type"] == "text" and parameter["key_id"] == "alias/aws/ssm", "DATABASE_URL encryption or data type mismatch")
    require(parameter["overwrite"] is False and parameter["value_wo_version"] == 1, "Existing values must not be overwritten")
    require(all(parameter.get(key) is None for key in ("value", "insecure_value", "value_wo")), "Parameter values must not be persisted in the plan")

    ingress = of_type("aws_vpc_security_group_ingress_rule")
    egress = of_type("aws_vpc_security_group_egress_rule")
    require(len(ingress) == 3 and len(egress) == 3, "Unexpected security group rules")
    require(all(r["change"]["after"].get("security_group_id") != "sg-db" for r in egress), "DB egress rules are forbidden")
    require(all(not r["change"]["after"].get("cidr_ipv4") for r in ingress), "Ingress must use prefix list or security group references")
    policy = json.loads(attrs("module.execution_policy.aws_iam_policy.this")["policy"])
    statements = {s["Sid"]: s for s in policy["Statement"]}
    parameter_arn = "arn:aws:ssm:ap-northeast-2:123456789012:parameter/sbh/platform/demo/backend/DATABASE_URL"
    require(parameter["arn"] == parameter_arn, "Created parameter and IAM/output ARN must match")
    require(set(statements) == {"EcrLogin", "PullBackendImage", "WriteTaskLogs", "ReadApplicationDatabaseUrl"}, "Unexpected execution role permissions")
    require(statements["ReadApplicationDatabaseUrl"]["Action"] == ["ssm:GetParameters"] and statements["ReadApplicationDatabaseUrl"]["Resource"] == parameter_arn, "Execution role must read only the DATABASE_URL parameter")
    require(statements["PullBackendImage"]["Resource"] == attrs("module.ecr.aws_ecr_repository.this")["arn"], "Image access must be scoped to backend ECR")
    require(statements["WriteTaskLogs"]["Resource"].endswith("log-group:sbh-platform-dev-log-api:log-stream:*"), "Logs must be scoped to backend streams")
    require(not any(a.startswith("module.task_role.aws_iam_role_policy_attachment") for a in resources), "Task role must not inherit execution permissions")
    require(attrs("module.ecs.aws_cloudwatch_log_group.this")["retention_in_days"] == 30, "Logs must be kept for 30 days")

    alb = attrs("module.alb.aws_lb.this")
    require(alb["name"] == "sbh-platform-dev-alb-api" and len(alb["name"]) <= 32, "ALB naming mismatch")
    require(alb["internal"] is True and alb["subnets"] == ["subnet-app-a", "subnet-app-c"], "ALB must be internal in app subnets")
    target = attrs('module.alb.aws_lb_target_group.this["api"]')
    require(target["name"] == "sbh-platform-dev-tg-api" and len(target["name"]) <= 32, "Target group naming mismatch")
    require(target["target_type"] == "ip" and target["port"] == port, "Fargate requires the correct IP target group")
    require(target["health_check"][0]["path"] == health_path, "Health path must propagate")
    require(attrs('module.alb.aws_lb_listener.forward["http"]')["port"] == 80, "ALB listener must be HTTP 80")

    distribution = attrs("module.cloudfront.aws_cloudfront_distribution.this")
    certificate = attrs("aws_acm_certificate.frontend")
    require(certificate["domain_name"] == "sbh.howon.me" and certificate["validation_method"] == "DNS", "ACM certificate must validate the custom domain with DNS")
    require(certificate["options"][0]["export"] == "DISABLED", "ACM certificate must not be exportable")
    require(distribution["aliases"] == ["sbh.howon.me"], "CloudFront alias mismatch")
    viewer = distribution["viewer_certificate"][0]
    require(viewer["acm_certificate_arn"] == certificate["arn"] and viewer["ssl_support_method"] == "sni-only", "CloudFront must use the ACM certificate with SNI")
    require(viewer["minimum_protocol_version"] == "TLSv1.2_2021", "CloudFront minimum TLS policy mismatch")
    origins = {o["origin_id"]: o for o in distribution["origin"]}
    require(set(origins) == {"frontend", "api"}, "CloudFront needs S3 and VPC origins")
    behaviors = {b["path_pattern"]: b for b in distribution["ordered_cache_behavior"]}
    require(set(behaviors) == {"/api", "/api/*", "/*.html", "/assets/*", "/static/*"}, "CloudFront path mapping mismatch")
    require(behaviors["/*.html"]["cache_policy_id"] == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad", "HTML cache must be disabled")
    for path in ["/api", "/api/*"]:
        b = behaviors[path]
        require(b["target_origin_id"] == "api" and b["cache_policy_id"] == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad", "API cache must be disabled")
        require(b["origin_request_policy_id"] == "b689b0a8-53d0-40ab-baf2-68738e2966ac" and not b["function_association"], "API auth forwarding and SPA separation mismatch")
    require(all(not e.get("response_page_path") and not e.get("response_code") and e["error_caching_min_ttl"] == 0 for e in distribution["custom_error_response"]), "Origin errors must stay unchanged")
    bucket_policy = json.loads(attrs("aws_s3_bucket_policy.frontend")["policy"])
    require(bucket_policy["Statement"][0]["Condition"]["StringEquals"]["AWS:SourceArn"] == distribution["arn"], "S3 access must be scoped to this distribution")
    require(attrs("module.frontend.aws_s3_bucket_versioning.this[0]")["versioning_configuration"][0]["status"] == "Enabled", "Frontend versioning must be enabled")
    bucket = attrs("module.frontend.aws_s3_bucket.this")["bucket"]
    require(bucket == "sbh-platform-dev-s3-web-123456789012" and len(bucket) <= 63, "S3 bucket naming mismatch")

    require(not of_type("aws_ecs_service") and not of_type("aws_ecs_task_definition"), "CI/CD must own Task Definition and Service")
    backend = plan["output_changes"]["backend"]["after"]
    required = {"ecr_repository_url", "cluster_name", "cluster_arn", "log_group_name", "target_group_arn", "ecs_security_group_id", "execution_role_arn", "task_role_arn", "container_name", "container_port"}
    require(required <= backend.keys(), "Missing CI/CD handoff output")
    require(not {"service_name", "service_arn", "task_definition_arn"} & backend.keys(), "Terraform must not output deployment-owned resources")
    require(backend["cluster_name"] == "sbh-platform-dev-ecs-api" and backend["log_group_name"] == "sbh-platform-dev-log-api", "ECS handoff mismatch")
    require(backend["target_group_arn"] == target["arn"] and backend["ecs_security_group_id"] == "sg-ecs", "ALB and network handoff mismatch")
    require(backend["container_name"] == "app" and backend["container_port"] == port, "Container handoff mismatch")
    require(plan["output_changes"]["network"]["after"]["app_subnet_ids"] == ["subnet-app-a", "subnet-app-c"], "App subnet handoff mismatch")
    require(plan["output_changes"]["database"]["after"]["database_url_parameter_arn"] == parameter_arn, "SSM handoff mismatch")
    require(plan["output_changes"]["database"]["after"]["name"] == "freesia", "Database output name must be freesia")
    require(plan["output_changes"]["database"]["after"]["master_secret_arn"] == master_secret["arn"], "Database output must point to the administrator Secret")


def main(path):
    events = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    summaries = [e["test_summary"] for e in events if e["type"] == "test_summary"]
    require(summaries and summaries[-1]["status"] == "pass" and summaries[-1]["passed"] == 4, "Terraform tests must all pass first")
    plans = {e["@testrun"]: e["test_plan"] for e in events if e["type"] == "test_plan"}
    for name, port, health_path in [("infrastructure_only", 8000, "/api/health"), ("custom_port_handoff", 9090, "/api/ready")]:
        require(name in plans, f"Missing mock plan: {name}")
        check_plan(plans[name], port, health_path)
        print(f"PASS: {name} full plan infrastructure and CI/CD handoff checks")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check-dev-test-plan.py dev-tests.jsonl")
    try:
        main(sys.argv[1])
    except (ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"FAIL: {error}") from error
