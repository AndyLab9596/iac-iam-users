locals {
  users_from_yaml = yamldecode(file("${path.module}/user-roles.yaml")).users
  users_map = {
    for user_config in local.users_from_yaml : user_config.username => user_config.roles
  }
}

resource "aws_iam_user" "users" {
  for_each = toset(local.users_from_yaml[*].username)
  name     = each.value
}

resource "aws_iam_user_login_profile" "users" {
  for_each        = aws_iam_user.users
  user            = each.value.name
  password_length = 8

  lifecycle {
    ignore_changes = [
      password_length,
      password_reset_required,
      pgp_key
    ]
  }
}

resource "local_file" "iam_users_csv" {
  filename = "${path.module}/iam_users.csv"
  content = join("\n", concat(
    ["username,password"],
    [
      for username, profile in aws_iam_user_login_profile.users : "${username},${profile.password}"
    ]
  ))
}

output "passwords" {
  sensitive = true
  value     = { for user, user_login in aws_iam_user_login_profile.users : user => user_login.password }
}

output "users_map" {
  value = local.users_map
}