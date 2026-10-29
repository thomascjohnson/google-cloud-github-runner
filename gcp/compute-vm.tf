locals {
  github_runners_types_map = {
    for type in var.github_runners_types : type.name => type
  }
}

# Create instance templates for each GitHub Actions runner type
# https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v53.0.0/modules/compute-vm/README.md
module "github-runners-vm-templates" {
  source   = "git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/compute-vm?ref=v53.0.0"
  for_each = local.github_runners_types_map

  project_id = module.project.project_id
  zone       = "${var.region}-${var.zone}"

  name          = each.value.name
  description   = "GitHub Actions runner template (${upper(each.value.arch)}), ${each.value.vcpu} vCPU, ${each.value.memory} GB memory, ${each.value.disk_size} GB SSD (Terraform-managed)"
  instance_type = each.value.instance_type
  min_cpu_platform = (
    each.value.min_cpu_platform == "" ? null : each.value.min_cpu_platform
  )

  network_interfaces = [{
    network    = module.vpc-github-runners.self_link
    subnetwork = module.vpc-github-runners.subnet_self_links["${var.region}/subnet-github-runners-${local.region_shortnames[var.region]}"]
  }]

  boot_disk = {
    initialize_params = {
      image = "projects/${module.project.project_id}/global/images/family/${each.value.image}" # Build via build-image-[...].sh
      type  = each.value.disk_type
      size  = each.value.disk_size
      # For hyperdisk-balanced
      provisioned_iops       = each.value.disk_provisioned_iops
      provisioned_throughput = each.value.disk_provisioned_throughput
    }
  }

  options = {
    termination_action = "DELETE"
    # Null for every lane that does not ask for it, so existing templates keep
    # their current plan. Nested virt does not need onHostMaintenance=TERMINATE
    # here - verified on n2 in this project with the policy left at MIGRATE.
    #
    # enable_turbo_mode must be stated, not omitted. Fabric declares the inner
    # attributes as optional(bool) with no default, so an omitted one is null,
    # and template.tf feeds it straight into a ternary condition - which fails
    # the plan with "Null condition" rather than treating null as false.
    advanced_machine_features = (
      each.value.enable_nested_virtualization ? {
        enable_nested_virtualization = true
        enable_turbo_mode            = false
      } : null
    )
    # https://docs.github.com/en/actions/reference/limits#existing-system-limits
    max_run_duration = {
      seconds = var.github_runners_max_run_duration
    }
  }

  service_account = {
    auto_create = false
    email       = module.service-account-compute-vm-github-runners.email
  }

  metadata = {
    startup-script = "# Overwritten by the GitHub Actions Runners manager during creation."
  }

  create_template = {
    regional = true
  }

  depends_on = [
    null_resource.build-github-runners-images,
    time_sleep.wait_for_service_account_compute_vm
  ]
}
