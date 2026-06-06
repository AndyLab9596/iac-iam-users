# Guideline Implementation: IAM Users and Roles với Terraform

## 1. Yêu cầu và kết quả cuối cùng

### Yêu cầu bài lab

Bạn cần xây dựng một Terraform project để quản lý IAM users và IAM roles trên AWS.

Thông tin user sẽ được khai báo trong file YAML. Mỗi user có một hoặc nhiều role được phép assume. Thông tin role và các AWS Managed Policies tương ứng sẽ được khai báo trong Terraform.

Bài lab cần đạt các yêu cầu sau:

1. Đọc danh sách users và roles từ file `user-roles.yaml`.
2. Tạo IAM users dựa trên danh sách users trong YAML.
3. Tạo login profile cho từng IAM user để user có thể login AWS Console.
4. Xuất username và temporary password ra file CSV phục vụ bài lab.
5. Tạo các IAM roles như `readonly`, `admin`, `auditor`, `developer`.
6. Attach AWS Managed Policies phù hợp vào từng IAM role.
7. Tạo trust relationship cho từng IAM role.
8. Đảm bảo user chỉ có thể assume đúng role được khai báo trong YAML.
9. Kiểm tra kết quả trên AWS Console.
10. Destroy toàn bộ resource sau khi hoàn thành bài lab.

### Kết quả cuối cùng đạt được

Sau khi hoàn thành, Terraform sẽ tạo ra:

- IAM users theo file YAML.
- Login profile cho từng IAM user.
- File `iam_users.csv` chứa `username,password`.
- IAM roles tương ứng với các nhóm quyền.
- Policy attachments cho từng role.
- Trust relationship riêng cho từng role, trong đó chỉ các users được gán role đó mới có quyền `sts:AssumeRole`.

Ví dụ kết quả logic:

```text
john  -> có thể assume readonly, developer
jane  -> có thể assume admin, auditor
lauro -> có thể assume readonly
```

Role `readonly` chỉ trust `john` và `lauro`.

Role `admin` chỉ trust `jane`.

Role `developer` chỉ trust `john`.

Role `auditor` chỉ trust `jane`.

## 2. Input tối thiểu để làm bài lab

### AWS credentials

Máy local cần có AWS credentials hợp lệ. Có thể cấu hình bằng một trong các cách sau:

```bash
aws configure
```

Hoặc dùng environment variables:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="ap-southeast-1"
```

Account dùng để chạy Terraform cần có quyền tạo và quản lý IAM resources.

### Terraform provider

Tối thiểu cần file `provider.tf`:

```hcl
terraform {
  required_version = "~> 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}
```

### YAML input

Tối thiểu cần file `user-roles.yaml`:

```yaml
users:
  - username: john
    roles: [readonly, developer]
  - username: jane
    roles: [admin, auditor]
  - username: lauro
    roles: [readonly]
```

### Role configuration

Tối thiểu cần có map role -> policies trong Terraform:

```hcl
locals {
  role_policies = {
    readonly = [
      "ReadOnlyAccess"
    ]

    admin = [
      "AdministratorAccess"
    ]

    auditor = [
      "SecurityAudit"
    ]

    developer = [
      "AmazonVPCFullAccess",
      "AmazonEC2FullAccess",
      "AmazonRDSFullAccess"
    ]
  }
}
```

## 3. Step by step implementation

### Step 1: Tạo Terraform provider

**Hint:** Trước khi tạo resource, Terraform cần biết provider nào sẽ được dùng và region AWS nào sẽ được thao tác.

Tạo file `provider.tf` và khai báo:

- Terraform version.
- AWS provider source.
- AWS provider version.
- AWS region.

Sau đó chạy:

```bash
terraform init
```

Kết quả mong đợi:

- Terraform download AWS provider.
- Thư mục `.terraform` được tạo.
- File `.terraform.lock.hcl` được tạo.

### Step 2: Tạo file YAML chứa users và roles

**Hint:** Không hardcode user trực tiếp trong resource. Hãy để user input nằm trong YAML để sau này chỉ cần sửa data, không cần sửa logic Terraform.

Tạo file `user-roles.yaml`:

```yaml
users:
  - username: john
    roles: [readonly, developer]
  - username: jane
    roles: [admin, auditor]
  - username: lauro
    roles: [readonly]
```

Ý nghĩa:

- `username` là tên IAM user cần tạo.
- `roles` là danh sách IAM roles mà user đó được phép assume.

### Step 3: Đọc YAML bằng Terraform

**Hint:** Terraform có function `file()` để đọc file và `yamldecode()` để convert YAML thành Terraform object.

Trong `users.tf`, tạo local:

```hcl
locals {
  users_from_yaml = yamldecode(file("${path.module}/user-roles.yaml")).users
}
```

Bạn có thể output thử để kiểm tra:

```hcl
output "users_from_yaml" {
  value = local.users_from_yaml
}
```

Chạy:

```bash
terraform plan
```

Kết quả mong đợi là Terraform đọc được list users từ YAML.

### Step 4: Tạo map username -> roles

**Hint:** Trust relationship cần biết mỗi user có những role nào. Vì vậy nên tạo một map để tra cứu nhanh bằng username.

Tạo local:

```hcl
locals {
  users_map = {
    for user_config in local.users_from_yaml : user_config.username => user_config.roles
  }
}
```

Kết quả logic:

```hcl
{
  john  = ["readonly", "developer"]
  jane  = ["admin", "auditor"]
  lauro = ["readonly"]
}
```

Map này sẽ dùng ở trust relationship để kiểm tra user nào được assume role nào.

### Step 5: Tạo IAM users

**Hint:** Khi muốn tạo nhiều resource cùng loại từ một list hoặc map, hãy dùng `for_each`.

Tạo resource:

```hcl
resource "aws_iam_user" "users" {
  for_each = toset(local.users_from_yaml[*].username)
  name     = each.value
}
```

Giải thích:

- `local.users_from_yaml[*].username` lấy danh sách username.
- `toset(...)` convert list thành set để dùng với `for_each`.
- `each.value` là username hiện tại.

Kết quả mong đợi:

- Tạo IAM users: `john`, `jane`, `lauro`.

### Step 6: Tạo login profile cho IAM users

**Hint:** IAM user muốn login AWS Console cần có login profile. Password nên xem là sensitive data.

Tạo resource:

```hcl
resource "aws_iam_user_login_profile" "users" {
  for_each        = aws_iam_user.users
  user            = each.value.name
  password_length = 8
}
```

Trong bài lab, có thể output password để kiểm tra. Trong production không nên xuất password dạng plain text.

Có thể thêm lifecycle để Terraform không cố thay đổi lại một số field không cần thiết:

```hcl
lifecycle {
  ignore_changes = [
    password_length,
    password_reset_required,
    pgp_key
  ]
}
```

### Step 7: Xuất username/password ra CSV

**Hint:** File CSV chỉ là một chuỗi text gồm nhiều dòng. Hãy tạo header trước, sau đó tạo từng dòng user bằng `for expression`, rồi nối lại bằng `join("\n", ...)`.

Tạo resource:

```hcl
resource "local_file" "iam_users_csv" {
  filename = "${path.module}/iam_users.csv"

  content = join("\n", concat(
    ["username,password"],
    [
      for username, profile in aws_iam_user_login_profile.users :
      "${username},${profile.password}"
    ]
  ))
}
```

Kết quả mong đợi:

```csv
username,password
john,<temporary-password>
jane,<temporary-password>
lauro,<temporary-password>
```

Lưu ý:

- File `iam_users.csv` chứa password, không commit lên Git.
- Nên thêm `iam_users.csv` vào `.gitignore`.
- Trong môi trường thật, nên dùng `pgp_key`, Secrets Manager, hoặc quy trình truyền secret an toàn hơn.

### Step 8: Khai báo role và policy mapping

**Hint:** Hãy tách phần role definition ra khỏi user definition. User nằm trong YAML, còn role và permission nằm trong Terraform.

Trong `roles.tf`, tạo local:

```hcl
locals {
  role_policies = {
    readonly = [
      "ReadOnlyAccess"
    ]

    admin = [
      "AdministratorAccess"
    ]

    auditor = [
      "SecurityAudit"
    ]

    developer = [
      "AmazonVPCFullAccess",
      "AmazonEC2FullAccess",
      "AmazonRDSFullAccess"
    ]
  }
}
```

Ý nghĩa:

- Key của map là role name.
- Value là list AWS Managed Policies cần attach vào role đó.

### Step 9: Flatten role -> policies

**Hint:** Một role có thể có nhiều policies. Resource `aws_iam_role_policy_attachment` attach từng policy một, nên cần chuyển dữ liệu thành list các cặp `role/policy`.

Tạo local:

```hcl
locals {
  role_policies_list = flatten([
    for role, policies in local.role_policies : [
      for policy in policies : {
        role   = role
        policy = policy
      }
    ]
  ])
}
```

Kết quả logic:

```hcl
[
  {
    role   = "readonly"
    policy = "ReadOnlyAccess"
  },
  {
    role   = "developer"
    policy = "AmazonVPCFullAccess"
  },
  {
    role   = "developer"
    policy = "AmazonEC2FullAccess"
  },
  {
    role   = "developer"
    policy = "AmazonRDSFullAccess"
  }
]
```

### Step 10: Lấy AWS account ID hiện tại

**Hint:** Trust policy cần ARN của IAM users. ARN có chứa AWS account ID, nên Terraform cần query account ID hiện tại.

Tạo data source:

```hcl
data "aws_caller_identity" "current" {}
```

Sau đó có thể build user ARN theo format:

```hcl
"arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${username}"
```

### Step 11: Tạo trust relationship riêng cho từng role

**Hint:** Trust relationship không cấp permission làm việc với AWS resources. Nó chỉ trả lời câu hỏi: principal nào được phép assume role này?

Tạo data source:

```hcl
data "aws_iam_policy_document" "assume_role_policy" {
  for_each = toset(keys(local.role_policies))

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"

      identifiers = [
        for username in keys(aws_iam_user.users) :
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${username}"
        if contains(local.users_map[username], each.value)
      ]
    }
  }
}
```

Giải thích quan trọng:

- `for_each = toset(keys(local.role_policies))` tạo một trust policy cho mỗi role.
- `each.value` là role hiện tại, ví dụ `readonly`.
- `keys(aws_iam_user.users)` lấy danh sách username đã tạo.
- `contains(local.users_map[username], each.value)` kiểm tra user đó có được gán role hiện tại không.
- Nếu đúng, user ARN được đưa vào `principals.identifiers`.

Ví dụ khi `each.value = "readonly"`:

```hcl
contains(local.users_map["john"], "readonly")  # true
contains(local.users_map["jane"], "readonly")  # false
contains(local.users_map["lauro"], "readonly") # true
```

Vì vậy trust relationship của role `readonly` chỉ chứa `john` và `lauro`.

### Step 12: Tạo IAM roles

**Hint:** Role cần có `assume_role_policy`. Đây chính là trust relationship đã tạo ở bước trước.

Tạo resource:

```hcl
resource "aws_iam_role" "roles" {
  for_each = toset(keys(local.role_policies))

  name               = each.key
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy[each.value].json
}
```

Kết quả mong đợi:

- IAM role `readonly`.
- IAM role `admin`.
- IAM role `auditor`.
- IAM role `developer`.

Mỗi role có trust relationship riêng.

### Step 13: Query AWS Managed Policies

**Hint:** Các policy như `ReadOnlyAccess` hoặc `AdministratorAccess` đã tồn tại sẵn trong AWS. Terraform chỉ cần đọc ARN của chúng bằng data source.

Tạo data source:

```hcl
data "aws_iam_policy" "managed_policies" {
  for_each = toset(local.role_policies_list[*].policy)
  arn      = "arn:aws:iam::aws:policy/${each.value}"
}
```

Ví dụ:

```text
ReadOnlyAccess -> arn:aws:iam::aws:policy/ReadOnlyAccess
```

### Step 14: Attach policies vào roles

**Hint:** Permission policy trả lời câu hỏi: sau khi assume role thành công, role đó được phép làm gì?

Tạo resource:

```hcl
resource "aws_iam_role_policy_attachment" "role_policy_attachments" {
  count = length(local.role_policies_list)

  role       = aws_iam_role.roles[local.role_policies_list[count.index].role].name
  policy_arn = data.aws_iam_policy.managed_policies[local.role_policies_list[count.index].policy].arn
}
```

Giải thích:

- `count` tạo số lượng attachment bằng số phần tử trong `role_policies_list`.
- `local.role_policies_list[count.index].role` lấy role hiện tại.
- `local.role_policies_list[count.index].policy` lấy policy hiện tại.
- Terraform attach policy tương ứng vào role tương ứng.

### Step 15: Format và validate Terraform code

**Hint:** Trước khi apply, luôn format và validate để bắt lỗi syntax sớm.

Chạy:

```bash
terraform fmt
terraform validate
```

Kết quả mong đợi:

- `terraform fmt` format lại `.tf` files.
- `terraform validate` báo configuration hợp lệ.

### Step 16: Review execution plan

**Hint:** Đọc `terraform plan` trước khi apply để biết Terraform sẽ tạo gì trong AWS account.

Chạy:

```bash
terraform plan
```

Kiểm tra plan có các resource chính:

- `aws_iam_user.users`
- `aws_iam_user_login_profile.users`
- `local_file.iam_users_csv`
- `aws_iam_role.roles`
- `aws_iam_role_policy_attachment.role_policy_attachments`

### Step 17: Apply Terraform

**Hint:** Chỉ apply khi plan đúng với mong đợi. IAM là phần nhạy cảm, đặc biệt với role `admin`.

Chạy:

```bash
terraform apply
```

Nhập:

```text
yes
```

Kết quả mong đợi:

- IAM users được tạo.
- IAM roles được tạo.
- Policies được attach.
- Trust relationships được cấu hình.
- File `iam_users.csv` được tạo local.

### Step 18: Kiểm tra trên AWS Console

**Hint:** Hãy kiểm tra cả hai phía: user có login được không, và role có trust đúng user không.

Kiểm tra IAM Users:

- Vào AWS Console.
- Mở IAM.
- Kiểm tra users `john`, `jane`, `lauro`.
- Xác nhận users có Console access.

Kiểm tra IAM Roles:

- Mở từng role: `readonly`, `admin`, `auditor`, `developer`.
- Kiểm tra tab Permissions.
- Kiểm tra tab Trust relationships.

Kết quả cần thấy:

- Role `readonly` trust đúng users có role `readonly`.
- Role `admin` trust đúng users có role `admin`.
- Role `developer` trust đúng users có role `developer`.
- Role `auditor` trust đúng users có role `auditor`.

### Step 19: Test assume role

**Hint:** Một user chỉ assume được role nếu cả hai điều kiện đúng: role trust user đó và user gọi được action `sts:AssumeRole`.

Trong bài lab này, trust policy đã giới hạn principal theo từng role.

Bạn có thể login bằng user trong `iam_users.csv`, sau đó thử Switch Role trên AWS Console.

Cần kiểm tra:

- `john` switch được sang `readonly`.
- `john` switch được sang `developer`.
- `john` không switch được sang `admin`.
- `jane` switch được sang `admin`.
- `jane` switch được sang `auditor`.
- `lauro` switch được sang `readonly`.
- `lauro` không switch được sang `developer` hoặc `admin`.

Nếu user chưa thể switch role, kiểm tra thêm:

- Trust relationship của role.
- Permission của user có cho phép gọi `sts:AssumeRole` hay không.
- Account ID và role name khi switch role.

### Step 20: Cleanup resources

**Hint:** IAM users, passwords và admin roles không nên để lại sau lab. Hãy destroy khi kiểm tra xong.

Chạy:

```bash
terraform destroy
```

Nhập:

```text
yes
```

Sau đó kiểm tra lại AWS Console để chắc chắn resources đã bị xóa.

## Ghi chú quan trọng

### Trust relationship vs permission policy

Trust relationship trả lời:

```text
Ai được phép assume role này?
```

Permission policy trả lời:

```text
Sau khi assume role, role này được phép làm gì?
```

Một role cần cả hai phần để hoạt động đúng:

```text
IAM User -> được trust bởi role -> assume role -> dùng permissions của role
```

### Về password trong CSV

File `iam_users.csv` có chứa password nên chỉ phù hợp cho bài lab.

Nên thêm vào `.gitignore`:

```gitignore
iam_users.csv
*.tfstate
*.tfstate.*
.terraform/
```

Trong production, không nên output password plain text. Nên dùng cơ chế an toàn hơn như `pgp_key`, AWS Secrets Manager, hoặc quy trình cấp credential nội bộ.

