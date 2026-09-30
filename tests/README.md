# 결합 테스트

루트 tests 디렉터리는 여러 재사용 모듈을 함께 호출할 때의 연결을 검증합니다. 각 모듈의 tests 디렉터리는 해당 모듈 하나의 설정을 검증합니다.

| 경로 | 검증 목적 |
|---|---|
| iam-composition | IAM Policy ARN을 Role에 연결하고, 생성한 Instance Profile 이름을 EC2에 전달하는 구성이 함께 계획되는지 확인합니다. |

iam-composition은 실제 환경의 Root Module이 아닌 테스트 전용 구성입니다. Terraform 1.7 이상과 AWS Provider가 필요합니다.

~~~sh
cd tests/iam-composition
terraform init -backend=false
terraform validate
terraform test
~~~

테스트는 mock provider Plan을 사용하므로 AWS 리소스를 생성하지 않습니다. 실제 AWS IAM 권한이나 EC2 실행 결과는 검증하지 않습니다. 이 디렉터리를 제거하면 Policy·Role·Instance Profile·EC2 사이의 결합 검증이 사라지므로 테스트를 다른 위치로 옮겨 동등하게 검증하기 전에는 유지합니다.
