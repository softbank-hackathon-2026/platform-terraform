variable "name" {
  description = "EC2 인스턴스와 Root EBS 볼륨에 적용할 이름입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name은 비어 있을 수 없습니다."
  }
}

variable "ami_id" {
  description = "생성할 EC2 인스턴스의 AMI ID입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.ami_id)) > 0
    error_message = "ami_id는 비어 있을 수 없습니다."
  }
}

variable "instance_type" {
  description = "EC2 인스턴스 유형입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.instance_type)) > 0
    error_message = "instance_type은 비어 있을 수 없습니다."
  }
}

variable "purchase_option" {
  description = "EC2 구매 옵션입니다. on-demand 또는 spot을 사용할 수 있습니다."
  type        = string
  default     = "on-demand"

  validation {
    condition     = contains(["on-demand", "spot"], var.purchase_option)
    error_message = "purchase_option은 on-demand 또는 spot이어야 합니다."
  }
}

variable "subnet_id" {
  description = "EC2 인스턴스를 생성할 Subnet ID입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.subnet_id)) > 0
    error_message = "subnet_id는 비어 있을 수 없습니다."
  }
}

variable "security_group_ids" {
  description = "EC2 인스턴스에 연결할 Security Group ID 집합입니다."
  type        = set(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "security_group_ids에는 하나 이상의 Security Group ID가 필요합니다."
  }
}

variable "key_name" {
  description = "선택적으로 연결할 EC2 Key Pair 이름입니다."
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "선택적으로 연결할 IAM Instance Profile 이름입니다."
  type        = string
  default     = null
}

variable "user_data" {
  description = "선택적 부트스트랩 스크립트입니다. 비밀번호나 토큰을 넣지 마세요."
  type        = string
  default     = null
}

variable "associate_public_ip_address" {
  description = "Public IP 자동 연결 여부입니다."
  type        = bool
  default     = false
}

variable "monitoring" {
  description = "상세 모니터링 활성화 여부입니다."
  type        = bool
  default     = false
}

variable "root_volume_size" {
  description = "암호화된 gp3 Root EBS 볼륨 크기이며 단위는 GiB입니다."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size > 0
    error_message = "root_volume_size는 0보다 커야 합니다."
  }
}

variable "root_volume_kms_key_id" {
  description = "Root EBS 암호화에 사용할 선택적 KMS Key ID 또는 ARN입니다. null이면 계정 기본 키를 사용합니다."
  type        = string
  default     = null
}

variable "tags" {
  description = "EC2 인스턴스와 Root EBS 볼륨에 적용할 추가 태그입니다."
  type        = map(string)
  default     = {}
}
