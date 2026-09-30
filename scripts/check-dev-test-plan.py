#!/usr/bin/env python3
"""Check child-module resources in the two full dev mock plans."""

import json
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_plan(plan, active):
    resources = {
        r["address"]: r for r in plan["resource_changes"] if r["mode"] == "managed"
    }

    def attrs(address):
        require(address in resources, f"Missing resource: {address}")
        return resources[address]["change"]["after"]

    def of_type(kind):
        return [r for r in resources.values() if r["type"] == kind]

    require(len(of_type("aws_subnet")) == 6, "Expected six subnets")
    require(len(of_type("aws_nat_gateway")) == 2, "Expected two NAT gateways")
    require(len(of_type("aws_eip")) == 2, "Expected two NAT EIPs")
    require(len(of_type("aws_route_table")) == 5, "Expected four private and one public route tables")
    for tier, base in [("public", 0), ("app", 10), ("db", 20)]:
        for offset, az in enumerate(["a", "c"]):
            group = "public" if tier == "public" else "private"
            subnet = attrs(f'module.network.aws_subnet.{group}["{tier}_{az}"]')
            require(subnet["cidr_block"] == f"10.20.{base + offset}.0/24", "Subnet CIDR mismatch")
            require(subnet["availability_zone"] == f"ap-northeast-2{az}", "Subnet AZ mismatch")
            require(subnet["map_public_ip_on_launch"] is False, "Public IP must be disabled")
    private_routes = [r for r in of_type("aws_route") if "private_" in r["address"]]
    require(len(private_routes) == 2, "DB subnets must have no default routes")
    for az in ["a", "c"]:
        route = attrs(f'module.network.aws_route.private_zonal["app_{az}"]')
        nat = attrs(f'module.network.aws_nat_gateway.zonal["ap-northeast-2{az}"]')
        require(route["nat_gateway_id"] == f"nat-app-{az}", "App NAT must be in the same AZ")
        require(nat["subnet_id"] == f"subnet-public-{az}", "NAT must be in the same AZ public subnet")

    db = attrs("module.database.aws_db_instance.primary")
    require(len(of_type("aws_db_instance")) == 1, "Standby must not be modeled as a read replica")
    for key, value in {
        "engine": "postgres", "engine_version": "17.11", "instance_class": "db.t4g.small",
        "multi_az": True, "storage_type": "gp3", "allocated_storage": 20,
        "storage_encrypted": True, "publicly_accessible": False,
        "backup_retention_period": 7, "deletion_protection": True,
        "skip_final_snapshot": False, "manage_master_user_password": True,
    }.items():
        require(db.get(key) == value, f"RDS {key} mismatch")
    require(db.get("password") is None and db.get("password_wo") is None, "No DB password may be stored")
    require(attrs("module.database.aws_db_subnet_group.this")["subnet_ids"] == ["subnet-db-a", "subnet-db-c"], "RDS must use DB subnets only")
    require(len(of_type("aws_secretsmanager_secret")) == 1 and not of_type("aws_secretsmanager_secret_version"), "Only app secret metadata is managed")

    ingress = of_type("aws_vpc_security_group_ingress_rule")
    egress = of_type("aws_vpc_security_group_egress_rule")
    require(len(ingress) == 3 and len(egress) == 3, "Unexpected security group rules")
    require(all(r["change"]["after"].get("security_group_id") != "sg-db" for r in egress), "DB egress rules are forbidden")
    require(all(not r["change"]["after"].get("cidr_ipv4") for r in ingress), "Ingress must use prefix list or security group references")
    policy = json.loads(attrs("module.execution_policy.aws_iam_policy.this")["policy"])
    statements = {s["Sid"]: s for s in policy["Statement"]}
    app_secret = attrs("aws_secretsmanager_secret.app_database")["arn"]
    require(statements["ReadApplicationDatabaseSecret"]["Resource"] == app_secret, "Execution role must use app secret only")
    require(statements["PullBackendImage"]["Resource"] == attrs("module.ecr.aws_ecr_repository.this")["arn"], "Image access must be scoped to backend ECR")
    require(statements["WriteTaskLogs"]["Resource"].endswith("log-group:/ecs/sbh-platform-dev-backend:log-stream:*"), "Logs must be scoped to backend streams")
    require(not any(a.startswith("module.task_role.aws_iam_role_policy_attachment") for a in resources), "Task role must not inherit execution permissions")
    require(attrs("module.ecs.aws_cloudwatch_log_group.this")["retention_in_days"] == 30, "Logs must be kept for 30 days")

    alb = attrs("module.alb.aws_lb.this")
    require(alb["internal"] is True and alb["subnets"] == ["subnet-app-a", "subnet-app-c"], "ALB must be internal in app subnets")
    target = attrs('module.alb.aws_lb_target_group.this["api"]')
    port = 9090 if active else 8080
    require(target["target_type"] == "ip" and target["port"] == port, "Fargate requires the correct IP target group")
    require(target["health_check"][0]["path"] == ("/api/ready" if active else "/api/health"), "Health path must propagate")
    require(attrs('module.alb.aws_lb_listener.forward["http"]')["port"] == 80, "ALB listener must be HTTP 80")

    distribution = attrs("module.cloudfront.aws_cloudfront_distribution.this")
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

    require(len(of_type("aws_ecs_service")) == int(active), "Service bootstrap mismatch")
    require(len(of_type("aws_ecs_task_definition")) == int(active), "Task bootstrap mismatch")
    if active:
        service = attrs('module.ecs.aws_ecs_service.this["this"]')
        task = attrs('module.ecs.aws_ecs_task_definition.this["this"]')
        require(service["desired_count"] == 2 and service["launch_type"] == "FARGATE", "Expected two On-Demand Fargate tasks")
        require(service["availability_zone_rebalancing"] == "ENABLED", "AZ rebalancing must be enabled")
        require(service["network_configuration"][0]["assign_public_ip"] is False, "Tasks must not have public IPs")
        require(service["network_configuration"][0]["subnets"] == ["subnet-app-a", "subnet-app-c"], "Tasks must use app subnets")
        require(task["cpu"] == "512" and task["memory"] == "1024", "Fargate size mismatch")
        require(task["runtime_platform"][0] == {"cpu_architecture": "X86_64", "operating_system_family": "LINUX"}, "Runtime platform mismatch")
        require(task["execution_role_arn"] != task["task_role_arn"], "Execution and task roles must be separate")
        container = json.loads(task["container_definitions"])[0]
        require(container["image"].endswith("@sha256:" + "a" * 64), "Image must be pinned to digest")
        require(container["portMappings"][0]["containerPort"] == port, "Container port must propagate")
        require(container["logConfiguration"]["options"]["awslogs-region"] == "ap-northeast-2", "Task logs must use Seoul")
        secrets = {s["name"]: s["valueFrom"] for s in container["secrets"]}
        require(secrets == {"DB_USERNAME": app_secret + ":username::", "DB_PASSWORD": app_secret + ":password::"}, "Tasks must use app secret JSON keys")
        require(all(e["name"] != "DB_PASSWORD" for e in container["environment"]), "Password must not be a plain environment value")


def main(path):
    events = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    summaries = [e["test_summary"] for e in events if e["type"] == "test_summary"]
    require(summaries and summaries[-1]["status"] == "pass" and summaries[-1]["passed"] == 3, "Terraform tests must all pass first")
    plans = {e["@testrun"]: e["test_plan"] for e in events if e["type"] == "test_plan"}
    for name, active in [("infrastructure_only", False), ("activate_two_tasks", True)]:
        require(name in plans, f"Missing mock plan: {name}")
        check_plan(plans[name], active)
        print(f"PASS: {name} full plan network, security, database and service checks")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check-dev-test-plan.py dev-tests.jsonl")
    try:
        main(sys.argv[1])
    except (ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"FAIL: {error}") from error
