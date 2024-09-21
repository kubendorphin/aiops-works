terraform {
  required_version = "> 0.13.0"
  required_providers { #引用腾讯云的库
    tencentcloud = {
      source  = "tencentcloudstack/tencentcloud"
      version = "1.81.5"
    }

    helm = { #引用helm库
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "helm" { #配置helm
  kubernetes {
    config_path = local_sensitive_file.kubeconfig.filename
  }
}